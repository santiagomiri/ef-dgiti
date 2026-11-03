terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Estado local: cada integrante despliega en su propia cuenta de AWS Academy.
  # En un equipo real se usaria un backend remoto compartido, por ejemplo:
  # backend "s3" {
  #   bucket       = "mi-bucket-de-estado"
  #   key          = "ef-dgiti/terraform.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  # Credenciales: las del Learner Lab de AWS Academy en ~/.aws/credentials.
  # Nunca se escriben en el codigo.
  region = var.aws_region

  default_tags {
    tags = {
      Proyecto   = var.project_name
      Curso      = "DGITI"
      Evaluacion = "EF"
      Gestion    = "Terraform"
    }
  }
}
