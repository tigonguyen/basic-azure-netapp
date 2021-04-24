variable "prefix" {
  description = "Specify a prefix for naming during entire the project"
  type        = string
  default     = "NetApp_test"
}

variable "rg_region" {
  description = "Specify where the related RG located"
  type        = string
  default     = "eastus"
}