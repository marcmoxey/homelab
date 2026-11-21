terraform {
  required_version = ">= 1.6"
  required_providers {
    b2 = {
      source  = "Backblaze/b2"
      version = "~> 0.13"
    }
  }
}

provider "b2" {}

