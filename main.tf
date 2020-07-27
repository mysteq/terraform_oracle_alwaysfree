/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/. */

variable "ssh_public_key" {
    default = "ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEA1CUuzbSdENgVB035n1DWBYobKzz9z0rcnfQmM6A6dKGQ5vMTtzLZh9ChHPKw8hLaDCojxKucs9o6qgG6EvoohNhOkUi0h+6reqjZXV2XnxPbTvttg0MtKf/LeDpJT1mOhS9wgWlR+V7dfpQwsf7OFsvwalE+U1lGN858JOLklfsvwSTzGdM/UlynfCmyrsD0PO0IAmb6OhmL5TBb38A9mgaiU0ip9tfLBo4K+6fBYZk1qWoKEO598NHOM916dwStS6Ngk3ciOfRok4rK52ffkY1CjYf6sr8NNKDlL7qV7DAGhcO15yAeydEwfld1opNKFs445XScqT+vMFnEJ9G71w== me@techie.cloud"
}

variable "tenancy_ocid" {
  default = "ocid1.tenancy.oc1..id"
}

variable "user_ocid" {
  default = "ocid1.user.oc1..id"
}

variable "fingerprint" {
    default = "00:00:00:00:00:00:00:00:00:00:00:00:00:00:00:00"
}

variable "private_key_path" {
    default = "~/.oci/oci_api_key.pem"
}

variable "region" {
    default = "eu-frankfurt-1"
}

variable "iaas_names" {
    type = list(string)
    default = ["FREE-OCI-VM01","FREE-OCI-VM02"]
}

variable "iaas_images" {
    # See https://docs.us-phoenix-1.oraclecloud.com/images/
    # Currently deploying Oracle-Autonomous-Linux-7.8-2020.06-1
    type = list(string)
    default = ["ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa3zdxgogqcjovlhvlxkdhsf2kxqluddyay2hvsmix67rujksol7ha", "ocid1.image.oc1.eu-frankfurt-1.aaaaaaaa3zdxgogqcjovlhvlxkdhsf2kxqluddyay2hvsmix67rujksol7ha"]
}

variable "iaas_availability_domain" {
    type = list(string)
    default = ["1","1"]
}

provider "oci" {
  tenancy_ocid = var.tenancy_ocid
  user_ocid = var.user_ocid
  fingerprint = var.fingerprint
  private_key_path = var.private_key_path
  region = var.region
}

data "oci_identity_availability_domain" "ad" {
  count = length(var.iaas_names)
  compartment_id = var.tenancy_ocid
  ad_number = var.iaas_availability_domain[count.index]
}

resource "oci_core_virtual_network" "free_oci_vcn" {
  cidr_block     = "10.254.0.0/16"
  compartment_id = var.tenancy_ocid
  display_name   = "OCI Lab VCN"
  dns_label      = "ocilabvcn"
}

resource "oci_core_subnet" "free_oci_subnet" {
  cidr_block        = "10.254.1.0/24"
  display_name      = "OCI Lab Subnet"
  dns_label         = "ocilabsubnet"
  security_list_ids = [oci_core_security_list.free_oci_security_list.id]
  compartment_id    = var.tenancy_ocid
  vcn_id            = oci_core_virtual_network.free_oci_vcn.id
  route_table_id    = oci_core_route_table.free_oci_route_table.id
  dhcp_options_id   = oci_core_virtual_network.free_oci_vcn.default_dhcp_options_id
}

resource "oci_core_internet_gateway" "free_oci_internet_gateway" {
  compartment_id = var.tenancy_ocid
  display_name   = "OCI Lab IG"
  vcn_id         = oci_core_virtual_network.free_oci_vcn.id
}

resource "oci_core_route_table" "free_oci_route_table" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_virtual_network.free_oci_vcn.id
  display_name   = "OCI Lab RouteTable"

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.free_oci_internet_gateway.id
  }
}

resource "oci_core_security_list" "free_oci_security_list" {
  compartment_id = var.tenancy_ocid
  vcn_id         = oci_core_virtual_network.free_oci_vcn.id
  display_name   = "OCI Lab SecurityList"

  egress_security_rules {
    protocol    = "6"
    destination = "0.0.0.0/0"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      max = "22"
      min = "22"
    }
  }
}

resource "oci_core_instance" "free_oci_instances" {
  count = length(var.iaas_names)
  availability_domain = data.oci_identity_availability_domain.ad[count.index].name
  compartment_id      = var.tenancy_ocid
  display_name        = var.iaas_names[count.index]
  shape               = "VM.Standard.E2.1.Micro"

  create_vnic_details {
    subnet_id        = oci_core_subnet.free_oci_subnet.id
    display_name     = join("_", [var.iaas_names[count.index], "vnic", count.index])
    assign_public_ip = true
    hostname_label   = var.iaas_names[count.index]
  }

  source_details {
    source_type = "image"
    source_id   = var.iaas_images[count.index]
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
  }
}

data "oci_core_volume_backup_policies" "free_oci_volume_backup_policies" { }

resource "oci_core_volume_backup_policy_assignment" "free_oci_boot_volume_backup_policy_assignment" {
  count = length(var.iaas_names)
  asset_id = oci_core_instance.free_oci_instances[count.index].boot_volume_id
  policy_id = data.oci_core_volume_backup_policies.free_oci_volume_backup_policies.volume_backup_policies.2.id
}

resource "oci_core_volume" "free_oci_volumes" {
  count = length(var.iaas_names)
  availability_domain = data.oci_identity_availability_domain.ad[count.index].name
  compartment_id = var.tenancy_ocid
  display_name     = join("_", [var.iaas_names[count.index], "blockvolume", count.index])
  backup_policy_id = data.oci_core_volume_backup_policies.free_oci_volume_backup_policies.volume_backup_policies.2.id
  size_in_gbs = "50"
}

resource "oci_core_volume_attachment" "free_oci_volume_attachments" {
  count = length(var.iaas_names)
  attachment_type = "iscsi"
  instance_id = oci_core_instance.free_oci_instances[count.index].id
  volume_id = oci_core_volume.free_oci_volumes[count.index].id
}
