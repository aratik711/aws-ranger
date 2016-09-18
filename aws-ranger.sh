#!/bin/bash

##Define the regions in aws
 locations=( us-east-1 us-west-2 us-west-1 eu-west-1 ap-southeast-1 ap-northeast-1 ap-southeast-2 sa-east-1 eu-central-1 ap-south-1 )

function check_pass
{
PASSWORD_FILE="/opt/secret"
MD5_HASH=$(cat /opt/secret)
PASSWORD_WRONG=1
COUNTER=1

while [ $COUNTER -le 3 ]
 do
    echo "Enter your password:"
    read -s ENTERED_PASSWORD
    if [ "$MD5_HASH" != "$(echo $ENTERED_PASSWORD | md5sum | cut -d '-' -f 1)" ]

then
        echo "Access Denied: Incorrect password!. Try again"
	COUNTER=$(( $COUNTER + 1 ))
    else
        echo "Access Granted"
        return 1
    fi
done
return 0
}

function del_all_un_vms
{

TS_TWO_HRS_AGO=`date --date="2 hours ago" +"%Y-%m-%dT%T.000Z"`
##Looping through each region
 for loc in "${locations[@]}"
 do
  ##Finding unnamed vms assigning to un_vms
   un_vms=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[?LaunchTime<=`'$TS_TWO_HRS_AGO'`].[State.Name,InstanceId,Tags[?Key==`Name`].Value | [0]]' --output text  --region=$loc | grep None | grep -E -v 'terminated|pending' | awk '{ print $2 }'))

  ##Looping through every regions unnamed vms
   for un_vm in "${un_vms[@]}"
   do
   ##Terminating unamed vms
     aws ec2 terminate-instances --output text --instance-ids=$un_vm --region=$loc
   done

 done
}

function del_all_vms_region
{
	region=$1
	all_vms=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[State.Name,InstanceId,Tags[?Key==`Name`].Value | [0]]' --output text  --region=$region | grep -E -v 'terminated' | awk '{ print $2 }'))
	for all_vm in "${all_vms[@]}"
   	do
   	##Terminating unamed vms
     		aws ec2 terminate-instances --output text --instance-ids=$all_vm --region=$region
   	done

}

function del_key_pairs_region
{
	region=$1
	all_key_pairs=($(aws ec2 describe-key-pairs  --query 'KeyPairs[*].[KeyName]'  --region=$region --output text ))
	vm_key_pairs=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[State.Name,KeyName]' --output text  --region=eu-west-1 | grep -E -v 'terminated' | awk '{ print $2 }'))
	unused_key_pairs=($(echo ${all_key_pairs[@]} ${vm_key_pairs[@]} | tr ' ' '\n' | sort | uniq -u ))
	for un_kp in "${unused_key_pairs[@]}"
	do
   		#Terminating unamed vms
		echo $un_kp
     		aws ec2 delete-key-pair --key-name $un_kp --region=$region
   	done
	


}


#del_all_un_vms
# Call getopt to validate the provided input.
options=$(getopt -o --long delete-all-vms:delete-key-pairs:info -- "$@")
[[ ! $1 ]] && {
	read -r -p "Delete orphan vms in all location(Y/N) " response
        response=${response,,}
        if [[ ! $response =~ ^(yes|y| ) ]]
        then
        	exit 1
        fi
 	echo 'Deleting orphan vms in all locations'
	del_all_un_vms
	exit 0;
 }
eval set -- "$options"
while [ $# -gt 0 ]
do
    case "$1" in
    --delete-all-vms)
	if check_pass; then
	exit 1
	fi
        shift; # The arg is next in position args
        region=$1
	del_all_vms_region $region
	;;    
    --delete-key-pairs)
	if check_pass; then
        exit 1
        fi
	shift;
	if [ -z $1 ]
	then
		read -r -p "Delete unused key pairs in all location(Y/N) " response
		response=${response,,}	
		if [[ ! $response =~ ^(yes|y| ) ]]
		then
			exit 1
		fi
		for region in "${locations[@]}"
		do
			echo "Deleting following key pairs in $region"
			echo "+------------------------------------------------+"
			del_key_pairs_region $region 
			echo "+------------------------------------------------+"
		done
	else
  		region=$1
	        echo "Deleting following key pairs in $region"
                echo "+------------------------------------------------+"
                del_key_pairs_region $region
                echo "+------------------------------------------------+"

	fi
	;;
   -h)
	man aws-ranger
	;;    
   --info)
	echo "Following are the various regions provided by AWS"
	echo "US East (N. Virginia)	us-east-1	
US West (N. California)	us-west-1	
US West (Oregon)	us-west-2	
Asia Pacific (Mumbai)	ap-south-1	
Asia Pacific (Seoul)	ap-northeast-2	
Asia Pacific (Singapore)	ap-southeast-1	
Asia Pacific (Sydney)	ap-southeast-2	
Asia Pacific (Tokyo)	ap-northeast-1	
EU (Frankfurt)	eu-central-1	
EU (Ireland)	eu-west-1	
South America (São Paulo)	sa-east-1"
	
	;;
   esac
    shift
done

