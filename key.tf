resource "aws_key_pair" "mykeypair" {
  key_name   = "mykeypair"
  public_key = file(var.public_key)
}