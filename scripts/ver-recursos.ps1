# Muestra con AWS CLI los recursos desplegados por Terraform.
# Uso (desde la raiz del repo):  .\scripts\ver-recursos.ps1
# Guarda una copia en scripts\recursos-resultado.txt

$out = Join-Path $PSScriptRoot "recursos-resultado.txt"
Start-Transcript -Path $out -Force | Out-Null

$vpc = terraform -chdir=infra output -raw vpc_id
$asg = terraform -chdir=infra output -raw asg_name
$tg  = terraform -chdir=infra output -raw target_group_arn

function Titulo($t) { Write-Host "`n==== $t ====" -ForegroundColor Cyan }

Titulo "Identidad (cuenta de AWS Academy)"
aws sts get-caller-identity --output table

Titulo "VPC"
aws ec2 describe-vpcs --vpc-ids $vpc --query "Vpcs[].{VPC:VpcId,CIDR:CidrBlock,Nombre:Tags[?Key=='Name']|[0].Value}" --output table

Titulo "Subredes (3 capas x 2 zonas)"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --query "sort_by(Subnets,&CidrBlock)[].{Nombre:Tags[?Key=='Name']|[0].Value,CIDR:CidrBlock,Zona:AvailabilityZone,IPPublica:MapPublicIpOnLaunch}" --output table

Titulo "Security Groups y reglas de entrada"
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" "Name=group-name,Values=*-sg-*" --query "SecurityGroups[].{SG:GroupName,Puerto:IpPermissions[0].FromPort,DesdeCIDR:IpPermissions[0].IpRanges[0].CidrIp,DesdeSG:IpPermissions[0].UserIdGroupPairs[0].GroupId,ID:GroupId}" --output table

Titulo "NAT Gateway"
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --query "NatGateways[].{NAT:NatGatewayId,Estado:State,Subred:SubnetId}" --output table

Titulo "Balanceador (ALB)"
aws elbv2 describe-load-balancers --query "LoadBalancers[?VpcId=='$vpc'].{Nombre:LoadBalancerName,DNS:DNSName,Estado:State.Code,Zonas:length(AvailabilityZones)}" --output table

Titulo "Salud de las instancias en el Target Group"
aws elbv2 describe-target-health --target-group-arn $tg --query "TargetHealthDescriptions[].{Instancia:Target.Id,Puerto:Target.Port,Zona:Target.AvailabilityZone,Estado:TargetHealth.State}" --output table

Titulo "Auto Scaling Group"
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asg --query "AutoScalingGroups[0].{Min:MinSize,Deseadas:DesiredCapacity,Max:MaxSize,HealthCheck:HealthCheckType}" --output table
aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names $asg --query "AutoScalingGroups[0].Instances[].{Instancia:InstanceId,Zona:AvailabilityZone,Estado:LifecycleState,Salud:HealthStatus}" --output table

Titulo "RDS: primaria y replica"
aws rds describe-db-instances --query "DBInstances[?starts_with(DBInstanceIdentifier,'ef-')].{BD:DBInstanceIdentifier,Clase:DBInstanceClass,Zona:AvailabilityZone,Estado:DBInstanceStatus,Publica:PubliclyAccessible,Cifrada:StorageEncrypted,ReplicaDe:ReadReplicaSourceDBInstanceIdentifier}" --output table

Titulo "Alarmas de CloudWatch"
aws cloudwatch describe-alarms --alarm-name-prefix "ef-" --query "MetricAlarms[].{Alarma:AlarmName,Estado:StateValue}" --output table

Stop-Transcript | Out-Null
Write-Host "`nCopia guardada en $out" -ForegroundColor Green
