# awsazurevpn
Create a site to site vpn using strongswan and a lot of tim tams and maybe sean's help

# Prerequisites
* azure cli
  * ```az login``` 
* aws cli
  * ```aws configure```
* SSH keys
  * Create your own keys
  * Import the key into aws as "vpnkey"
  * Modify the public key in the two .tf files ...

# Get Started
Run ```terraform init``` in the project directory (this) to initialise the working directory.
Run ```terraform apply```.

Right now you seem to need to restart strongswan after creation.

# Test
Log onto the VPN server(s)
```sudo ipsec statusall```
