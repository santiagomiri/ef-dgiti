# =============================================================================
# main.tf - Evaluacion Final DGITI
#
#   1. Datos de la cuenta y AMI
#   2. Red: VPC, 6 subredes en 2 AZ, Internet Gateway, NAT Gateway, rutas
#   3. Security Groups encadenados: Internet -> ALB -> App -> BD
#   4. Base de datos: RDS PostgreSQL primaria + replica de lectura
#   5. Almacenamiento: bucket S3 para los logs de acceso del ALB
#   6. Balanceador: ALB + Target Group + Listener HTTP
#   7. Computo: Launch Template + Auto Scaling Group + escalado por CPU
#   8. Monitoreo: dashboard y alarmas de CloudWatch
# =============================================================================

# ------------------------------------------------------------ 1. Datos ----
data "aws_caller_identity" "current" {}

# Cuenta de AWS del servicio ELB en la region (escribe los logs en S3)
data "aws_elb_service_account" "main" {}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  name = var.project_name

  # Plan B sin NAT: las instancias quedan en las subredes publicas
  app_subnet_ids = var.enable_nat_gateway ? aws_subnet.app[*].id : aws_subnet.public[*].id
}

# --------------------------------------------------------------- 2. Red ----
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true # necesario para resolver el endpoint de RDS
  enable_dns_hostnames = true

  tags = { Name = "${local.name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-igw" }
}

# Capa publica: solo el ALB y el NAT Gateway
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${local.name}-subnet-publica-${count.index + 1}", Capa = "publica" }
}

# Capa de aplicacion: instancias EC2 sin IP publica
resource "aws_subnet" "app" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name}-subnet-app-${count.index + 1}", Capa = "aplicacion" }
}

# Capa de datos: aislada, sin ruta a Internet
resource "aws_subnet" "db" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = { Name = "${local.name}-subnet-bd-${count.index + 1}", Capa = "datos" }
}

resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = { Name = "${local.name}-eip-nat" }
}

# Un solo NAT para reducir costo en el laboratorio (en produccion: uno por AZ)
resource "aws_nat_gateway" "main" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags       = { Name = "${local.name}-nat" }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name}-rt-publica" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Las instancias salen a Internet (dnf, pip, git clone) solo a traves del NAT
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-app" }
}

resource "aws_route" "app_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.app.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[0].id
}

resource "aws_route_table_association" "app" {
  count          = 2
  subnet_id      = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app.id
}

# Tabla de la capa de datos: solo la ruta local de la VPC
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-rt-bd" }
}

resource "aws_route_table_association" "db" {
  count          = 2
  subnet_id      = aws_subnet.db[count.index].id
  route_table_id = aws_route_table.db.id
}

# --------------------------------------------------- 3. Security Groups ----
# Cadena de minimo privilegio: cada capa solo acepta trafico de la anterior.

resource "aws_security_group" "alb" {
  name        = "${local.name}-sg-alb"
  description = "ALB: HTTP desde Internet, salida solo hacia las instancias"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-sg-alb" }
}

resource "aws_security_group" "app" {
  name        = "${local.name}-sg-app"
  description = "Instancias: puerto de la API solo desde el ALB"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-sg-app" }
}

resource "aws_security_group" "db" {
  name        = "${local.name}-sg-db"
  description = "RDS: PostgreSQL solo desde las instancias de la aplicacion"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${local.name}-sg-db" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  for_each          = toset(var.allowed_http_cidrs)
  security_group_id = aws_security_group.alb.id
  description       = "HTTP desde ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Trafico y health checks hacia las instancias"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "API solo desde el ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = var.app_port
  to_port                      = var.app_port
}

resource "aws_vpc_security_group_egress_rule" "app_https" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS saliente (GitHub, PyPI, repositorios dnf) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

resource "aws_vpc_security_group_egress_rule" "app_http" {
  security_group_id = aws_security_group.app.id
  description       = "HTTP saliente (repositorios de paquetes) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
}

resource "aws_vpc_security_group_egress_rule" "app_to_db" {
  security_group_id            = aws_security_group.app.id
  description                  = "PostgreSQL hacia RDS"
  referenced_security_group_id = aws_security_group.db.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "db_from_app" {
  security_group_id            = aws_security_group.db.id
  description                  = "PostgreSQL solo desde sg-app"
  referenced_security_group_id = aws_security_group.app.id
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
# sg-db no tiene reglas de salida: la BD no inicia conexiones.

# ---------------------------------------------------- 4. Base de datos ----
resource "aws_db_subnet_group" "main" {
  name       = "${local.name}-db-subnets"
  subnet_ids = aws_subnet.db[*].id
  tags       = { Name = "${local.name}-db-subnets" }
}

resource "aws_db_instance" "primary" {
  identifier     = "${local.name}-db-primaria"
  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password
  port     = 5432

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  availability_zone      = var.db_multi_az ? null : var.availability_zones[0]
  multi_az               = var.db_multi_az
  publicly_accessible    = false

  # Las copias automaticas son obligatorias para poder crear la replica
  backup_retention_period  = 1
  delete_automated_backups = true
  skip_final_snapshot      = true
  deletion_protection      = false
  apply_immediately        = true

  tags = { Name = "${local.name}-db-primaria", Rol = "escritura" }
}

resource "aws_db_instance" "replica" {
  identifier          = "${local.name}-db-replica"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.db_instance_class

  # Hereda motor, credenciales, cifrado y grupo de subredes de la primaria
  vpc_security_group_ids = [aws_security_group.db.id]
  availability_zone      = var.availability_zones[1]
  publicly_accessible    = false
  storage_encrypted      = true

  backup_retention_period = 0
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = { Name = "${local.name}-db-replica", Rol = "lectura" }
}

# ---------------------------------------------------- 5. Almacenamiento ----
resource "aws_s3_bucket" "alb_logs" {
  count         = var.enable_alb_access_logs ? 1 : 0
  bucket        = "${local.name}-alb-logs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # permite terraform destroy aunque tenga logs

  tags = { Name = "${local.name}-alb-logs" }
}

resource "aws_s3_bucket_public_access_block" "alb_logs" {
  count                   = var.enable_alb_access_logs ? 1 : 0
  bucket                  = aws_s3_bucket.alb_logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # los logs del ALB requieren SSE-S3
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  rule {
    id     = "expirar-logs"
    status = "Enabled"
    filter {}

    expiration {
      days = 7
    }
  }
}

resource "aws_s3_bucket_policy" "alb_logs" {
  count  = var.enable_alb_access_logs ? 1 : 0
  bucket = aws_s3_bucket.alb_logs[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "EscrituraDelServicioELB"
      Effect    = "Allow"
      Principal = { AWS = data.aws_elb_service_account.main.arn }
      Action    = "s3:PutObject"
      Resource  = "${aws_s3_bucket.alb_logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.alb_logs]
}

# ------------------------------------------------------- 6. Balanceador ----
resource "aws_lb" "main" {
  name                       = "${local.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.enable_alb_access_logs ? [1] : []
    content {
      bucket  = aws_s3_bucket.alb_logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  tags       = { Name = "${local.name}-alb" }
  depends_on = [aws_s3_bucket_policy.alb_logs]
}

resource "aws_lb_target_group" "app" {
  name                          = "${local.name}-tg"
  port                          = var.app_port
  protocol                      = "HTTP"
  vpc_id                        = aws_vpc.main.id
  target_type                   = "instance"
  load_balancing_algorithm_type = "round_robin"
  deregistration_delay          = 30 # drenado corto: despliegues mas rapidos

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  # Sin afinidad de sesion: cada solicitud puede ir a otra instancia
  stickiness {
    type    = "lb_cookie"
    enabled = false
  }

  tags = { Name = "${local.name}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ------------------------------------------------------------ 7. Computo ----
resource "aws_launch_template" "app" {
  name_prefix            = "${local.name}-lt-"
  image_id               = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  vpc_security_group_ids = [aws_security_group.app.id]
  update_default_version = true

  # replace(): quita los \r si el archivo llego con saltos de linea de Windows
  user_data = base64encode(replace(templatefile("${path.module}/user_data.sh", {
    repo_url        = var.app_repo_url
    repo_branch     = var.app_repo_branch
    app_port        = var.app_port
    db_host         = aws_db_instance.primary.address
    db_replica_host = aws_db_instance.replica.address
    db_name         = var.db_name
    db_user         = var.db_username
    db_password     = var.db_password
    app_env         = "aws-${var.aws_region}"
  }), "\r", ""))

  dynamic "iam_instance_profile" {
    for_each = var.instance_profile_name != "" ? [1] : []
    content {
      name = var.instance_profile_name
    }
  }

  # Metricas cada 1 minuto: el escalado reacciona rapido en la prueba de carga
  monitoring {
    enabled = true
  }

  # IMDSv2 obligatorio (token de sesion)
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${local.name}-app" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${local.name}-app-disco" }
  }
}

resource "aws_autoscaling_group" "app" {
  name                      = "${local.name}-asg"
  min_size                  = var.asg_min_size
  desired_capacity          = var.asg_desired_capacity
  max_size                  = var.asg_max_size
  vpc_zone_identifier       = local.app_subnet_ids
  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB" # reemplaza instancias que fallan /health
  health_check_grace_period = 360
  default_instance_warmup   = 120
  wait_for_capacity_timeout = "15m"

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version
  }

  # Si cambia el Launch Template, reemplazo gradual sin caida del servicio
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  enabled_metrics = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
  metrics_granularity = "1Minute"

  tag {
    key                 = "Name"
    value               = "${local.name}-app"
    propagate_at_launch = true
  }

  lifecycle {
    # La capacidad deseada la maneja la politica de escalado, no Terraform
    ignore_changes = [desired_capacity]
  }

  depends_on = [
    aws_route.app_nat,
    aws_route_table_association.app,
    aws_route_table_association.public,
  ]
}

resource "aws_autoscaling_policy" "cpu" {
  name                   = "${local.name}-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.cpu_target
  }
}

# --------------------------------------------------------- 8. Monitoreo ----
locals {
  alb_dim = { LoadBalancer = aws_lb.main.arn_suffix }
  tg_dims = {
    LoadBalancer = aws_lb.main.arn_suffix
    TargetGroup  = aws_lb_target_group.app.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${local.name}-instancias-no-saludables"
  alarm_description   = "Alguna instancia del Target Group falla el health check /health"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dims
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "target_5xx" {
  alarm_name          = "${local.name}-errores-5xx"
  alarm_description   = "Mas de 10 respuestas 5XX por minuto desde las instancias"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = local.alb_dim
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${local.name}-latencia-p95"
  alarm_description   = "Latencia p95 del ALB mayor a 1 segundo durante 2 minutos"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.alb_dim
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu-alta"
  alarm_description   = "CPU de la BD primaria mayor a 80%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.primary.identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = local.name

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "text", x = 0, y = 0, width = 24, height = 2
        properties = {
          markdown = "## EF DGITI - Monitoreo\nTrafico: **Usuarios -> ALB -> Auto Scaling Group (2 AZ) -> RDS primaria / replica**. ALB: `${aws_lb.main.dns_name}`"
        }
      },
      {
        type = "metric", x = 0, y = 2, width = 8, height = 6
        properties = {
          title  = "Solicitudes al ALB (por minuto)"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.main.arn_suffix, { label = "Total" }],
            ["AWS/ApplicationELB", "RequestCountPerTarget", "TargetGroup", aws_lb_target_group.app.arn_suffix, { label = "Por instancia" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 2, width = 8, height = 6
        properties = {
          title  = "Tiempo de respuesta (segundos)"
          region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.main.arn_suffix, { stat = "p50", label = "p50" }],
            ["...", { stat = "p95", label = "p95" }],
            ["...", { stat = "p99", label = "p99" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 2, width = 8, height = 6
        properties = {
          title  = "Codigos HTTP"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Sum"
          metrics = [
            ["AWS/ApplicationELB", "HTTPCode_Target_2XX_Count", "LoadBalancer", aws_lb.main.arn_suffix, { label = "2XX", color = "#2ca02c" }],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { label = "5XX instancias", color = "#d62728" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", ".", { label = "5XX ALB", color = "#ff7f0e" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 8, width = 8, height = 6
        properties = {
          title  = "Instancias saludables en el Target Group"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Maximum"
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.main.arn_suffix, { label = "Saludables", color = "#2ca02c" }],
            [".", "UnHealthyHostCount", ".", ".", ".", ".", { label = "No saludables", color = "#d62728" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 8, width = 8, height = 6
        properties = {
          title  = "CPU de las instancias EC2 (%)"
          region = var.aws_region, view = "timeSeries", period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.app.name, { stat = "Average", label = "Promedio ASG" }],
            [{ expression = "SEARCH('{AWS/EC2,InstanceId} MetricName=\"CPUUtilization\"', 'Average', 60)", id = "porinstancia", label = "" }],
          ]
          annotations = { horizontal = [{ label = "Objetivo de escalado", value = var.cpu_target }] }
        }
      },
      {
        type = "metric", x = 16, y = 8, width = 8, height = 6
        properties = {
          title  = "Auto Scaling Group: instancias"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Average"
          metrics = [
            ["AWS/AutoScaling", "GroupInServiceInstances", "AutoScalingGroupName", aws_autoscaling_group.app.name, { label = "En servicio" }],
            [".", "GroupDesiredCapacity", ".", ".", { label = "Deseadas" }],
            [".", "GroupPendingInstances", ".", ".", { label = "Iniciando" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 14, width = 8, height = 6
        properties = {
          title  = "RDS: CPU (%)"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Average"
          metrics = [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.primary.identifier, { label = "Primaria" }],
            ["...", aws_db_instance.replica.identifier, { label = "Replica" }],
          ]
        }
      },
      {
        type = "metric", x = 8, y = 14, width = 8, height = 6
        properties = {
          title  = "RDS: conexiones"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Average"
          metrics = [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", aws_db_instance.primary.identifier, { label = "Primaria" }],
            ["...", aws_db_instance.replica.identifier, { label = "Replica" }],
          ]
        }
      },
      {
        type = "metric", x = 16, y = 14, width = 8, height = 6
        properties = {
          title  = "RDS: retraso de replicacion (segundos)"
          region = var.aws_region, view = "timeSeries", period = 60, stat = "Maximum"
          metrics = [
            ["AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", aws_db_instance.replica.identifier, { label = "ReplicaLag" }],
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 20, width = 24, height = 3
        properties = {
          title = "Alarmas"
          alarms = [
            aws_cloudwatch_metric_alarm.unhealthy_hosts.arn,
            aws_cloudwatch_metric_alarm.target_5xx.arn,
            aws_cloudwatch_metric_alarm.latency_p95.arn,
            aws_cloudwatch_metric_alarm.rds_cpu.arn,
          ]
        }
      },
    ]
  })
}
