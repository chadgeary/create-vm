# Reference
Creates a VM via PowerCLI in a VMware vSphere environment

# Linux Clients
Instructions to install Powershell / PowerCLI (CentOS/RHEL/Fedora)
```
# add repository key
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
 
# add repository
curl https://packages.microsoft.com/config/rhel/7/prod.repo | sudo tee /etc/yum.repos.d/microsoft.repo
 
# install powershell
sudo yum -y install powershell
 
# For single user installation, replace AllUsers with CurrentUser and remove sudo for commands below
 
# Install PowerCLI module
sudo pwsh -c "Install-Module VMware.PowerCLI -Scope AllUsers -Force -confirm:\$False"
 
# Do not participate in CEIP
sudo pwsh -c "Set-PowerCLIConfiguration -Scope AllUsers -ParticipateInCEIP \$False -confirm:\$False"
 
# Ignore Certificate Errors
sudo pwsh -c "Set-PowerCLICOnfiguration -Scope AllUsers -InvalidCertificateAction ignore -confirm:\$false"
 
# Set timeout to 60 minutes (or more) for long operations (e.g. deploy / migrate)
sudo pwsh -c "Set-PowerCLIConfiguration -Scope AllUsers -WebOperationTimeoutSeconds 3600 -confirm:\$false"
 
# Set default multi-vcenter server connectivity
sudo pwsh -c "Set-PowerCLIConfiguration -Scope AllUsers -DefaultVIServerMode multiple -confirm:\$false"
```
