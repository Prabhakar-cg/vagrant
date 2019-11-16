resource "aws_instance" "temenos" {
  count                                = "1"
  ami                                  = "ami-23452"
  key_name                             = "test"
  subnet_id                            = "test"
  instance_type                        = "test"
  security_groups                      = ["test"]
  availability_zone                    = "test"
                                     
  tags {                                  
  OS                                   = "test"
   }
}
