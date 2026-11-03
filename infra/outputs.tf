output "alb_url" {
  description = "URL publica del servicio (a traves del balanceador)"
  value       = "http://${aws_lb.main.dns_name}"
}

output "endpoints" {
  description = "Endpoints para validar el servicio"
  value = {
    inicio  = "http://${aws_lb.main.dns_name}/"
    health  = "http://${aws_lb.main.dns_name}/health"
    status  = "http://${aws_lb.main.dns_name}/api/status"
    items   = "http://${aws_lb.main.dns_name}/api/items"
    compute = "http://${aws_lb.main.dns_name}/api/compute?n=20000"
    swagger = "http://${aws_lb.main.dns_name}/docs"
  }
}

output "asg_name" {
  description = "Auto Scaling Group de la aplicacion"
  value       = aws_autoscaling_group.app.name
}

output "target_group_arn" {
  description = "Target Group del ALB (para ver la salud de las instancias)"
  value       = aws_lb_target_group.app.arn
}

output "rds_primary_endpoint" {
  description = "Endpoint de la BD primaria (escrituras). Solo accesible desde sg-app"
  value       = aws_db_instance.primary.address
}

output "rds_replica_endpoint" {
  description = "Endpoint de la replica de lectura. Solo accesible desde sg-app"
  value       = aws_db_instance.replica.address
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "subnets" {
  description = "Subredes por capa"
  value = {
    publicas   = aws_subnet.public[*].id
    aplicacion = aws_subnet.app[*].id
    datos      = aws_subnet.db[*].id
  }
}

output "security_groups" {
  description = "Security Groups encadenados ALB -> App -> BD"
  value = {
    alb = aws_security_group.alb.id
    app = aws_security_group.app.id
    db  = aws_security_group.db.id
  }
}

output "alb_logs_bucket" {
  description = "Bucket S3 con los logs de acceso del ALB"
  value       = var.enable_alb_access_logs ? aws_s3_bucket.alb_logs[0].id : "deshabilitado"
}

output "cloudwatch_dashboard_url" {
  description = "Dashboard de CloudWatch"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards/dashboard/${aws_cloudwatch_dashboard.main.dashboard_name}"
}

output "github_actions_variables" {
  description = "Valores para Settings > Secrets and variables > Actions > Variables del repositorio"
  value = {
    AWS_REGION = var.aws_region
    ASG_NAME   = aws_autoscaling_group.app.name
    ALB_URL    = "http://${aws_lb.main.dns_name}"
  }
}

output "comando_prueba_carga" {
  description = "Comando k6 listo para copiar (ejecutar desde la raiz del repositorio)"
  value       = "k6 run -e BASE_URL=http://${aws_lb.main.dns_name} -e PERFIL=estres load-tests/carga.js"
}
