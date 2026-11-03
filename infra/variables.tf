# ------------------------------------------------------------- General ----
variable "aws_region" {
  description = "Region de AWS donde se despliega todo"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefijo de los nombres de los recursos (minusculas, numeros y guiones)"
  type        = string
  default     = "ef-dgiti"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.project_name))
    error_message = "project_name: 3 a 20 caracteres, minusculas, numeros y guiones."
  }
}

# ------------------------------------------------------------------ Red ----
variable "vpc_cidr" {
  description = "Bloque CIDR de la VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Dos zonas de disponibilidad (alta disponibilidad)"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Se requieren exactamente 2 zonas de disponibilidad."
  }
}

variable "public_subnet_cidrs" {
  description = "Subredes publicas (ALB y NAT Gateway), una por AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "app_subnet_cidrs" {
  description = "Subredes privadas de aplicacion (instancias EC2), una por AZ"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

variable "db_subnet_cidrs" {
  description = "Subredes privadas aisladas de base de datos (sin salida a Internet), una por AZ"
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24"]
}

variable "enable_nat_gateway" {
  description = "true = EC2 en subredes privadas con salida por NAT. false = EC2 en subredes publicas (plan B si el Learner Lab no permite NAT); el SG igual solo acepta trafico del ALB"
  type        = bool
  default     = true
}

variable "allowed_http_cidrs" {
  description = "Origenes permitidos hacia el ALB en el puerto 80"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# -------------------------------------------------------------- Computo ----
variable "instance_type" {
  description = "Tipo de instancia EC2 de la aplicacion"
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "Puerto en el que escucha la API (uvicorn) dentro de cada instancia"
  type        = number
  default     = 8000
}

variable "asg_min_size" {
  description = "Minimo de instancias del Auto Scaling Group (>= 2 para alta disponibilidad)"
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Instancias deseadas al crear el Auto Scaling Group"
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximo de instancias al escalar por carga"
  type        = number
  default     = 4
}

variable "cpu_target" {
  description = "CPU promedio (%) que la politica de escalado intenta mantener"
  type        = number
  default     = 50
}

variable "key_name" {
  description = "Par de claves para SSH (opcional; en el Learner Lab suele ser vockey). Vacio = sin SSH"
  type        = string
  default     = ""
}

variable "instance_profile_name" {
  description = "Perfil IAM opcional para las instancias (p. ej. LabInstanceProfile si existe). Vacio = ninguno"
  type        = string
  default     = ""
}

# ---------------------------------------------------------- Aplicacion ----
variable "app_repo_url" {
  description = "URL HTTPS del repositorio publico de GitHub que clonan las instancias al arrancar"
  type        = string

  validation {
    condition     = can(regex("^https://", var.app_repo_url))
    error_message = "app_repo_url debe empezar por https://"
  }
}

variable "app_repo_branch" {
  description = "Rama que se despliega"
  type        = string
  default     = "main"
}

# ------------------------------------------------------- Base de datos ----
variable "db_engine_version" {
  description = "Version mayor de PostgreSQL en RDS"
  type        = string
  default     = "16"
}

variable "db_instance_class" {
  description = "Clase de las instancias RDS (primaria y replica)"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Nombre de la base de datos"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Usuario maestro de la base de datos"
  type        = string
  default     = "appadmin"
}

variable "db_password" {
  description = "Contrasena del usuario maestro. Solo en terraform.tfvars (que NO se sube a Git) o en TF_VAR_db_password"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[A-Za-z0-9]{12,40}$", var.db_password))
    error_message = "db_password: 12 a 40 caracteres, solo letras y numeros."
  }
}

variable "db_multi_az" {
  description = "Multi-AZ en la primaria (standby sincrono). Desactivado por costo/tiempo: la replica ya esta en otra AZ"
  type        = bool
  default     = false
}

# ---------------------------------------------------------- Monitoreo ----
variable "enable_alb_access_logs" {
  description = "Guardar los logs de acceso del ALB en un bucket S3"
  type        = bool
  default     = true
}
