# EC2 Instance related details

## Hardware/Software of Instance
* type: t2.medium
* public IP: 54.158.127.254
* OS: Ubuntu 20.04
* storage:
  * base: 64 Gb
  * EBS volume: coming soon

## Open Incoming Ports
* ssh
* HTTP
* HTTPS

## Alarms
This instance currently has three CloudWatch alarms set:
* failed instance status check
* low disk space on root (/)
* low disk space on EBS Volume
* CPU credits low

The first alarm is created in the AWS -> EC2 -> specific instance -> status checks tab -> Actions -> create status check alarm
The remaining alarms are created in AWS -> CloudWatch -> Metrics
