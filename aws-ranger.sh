#!/bin/bash

##Define the regions in aws
declare -A locations=( ["us-east-1"]="Virginia" ["us-west-1"]="California" ["us-west-2"]="Oregon" ["ap-south-1"]="Mumbai" ["ap-northeast-2"]="Seoul" ["ap-southeast-1"]="Singapore" ["ap-southeast-2"]="Sydney" ["ap-northeast-1"]="Tokyo" ["eu-central-1"]="Frankfurt" ["eu-west-1"]="Ireland" ["sa-east-1"]="Sau Paulo" )

LOG="/home/compose/log/aws-ranger.log"

function check_pass
{
PASSWORD_FILE="/opt/secret"
MD5_HASH=$(cat /opt/secret)
PASSWORD_WRONG=1
COUNTER=1

while [ $COUNTER -le 3 ]
 do
    echo "Enter your password:" | tee -a $LOG
    read -s ENTERED_PASSWORD
    if [ "$MD5_HASH" != "$(echo $ENTERED_PASSWORD | md5sum | cut -d '-' -f 1)" ]

then
        echo "Access Denied: Incorrect password!. Try again" | tee -a $LOG 
	COUNTER=$(( $COUNTER + 1 ))
    else
        echo "Access Granted" | tee -a $LOG
        return 1
    fi
done
return 0
}

function del_all_un_vms
{

TS_TWO_HRS_AGO=`date --date="2 hours ago" +"%Y-%m-%dT%T.000Z"`
##Looping through each region
 for loc in "${!locations[@]}"
 do
  ##Finding unnamed vms assigning to un_vms
   un_vms=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[?LaunchTime<=`'$TS_TWO_HRS_AGO'`].[State.Name,InstanceId,Tags[?Key==`Name`].Value | [0]]' --output text  --region=$loc | grep None | grep -E -v 'terminated|pending' | awk '{ print $2 }'))

  ##Looping through every regions unnamed vms
   for un_vm in "${un_vms[@]}"
   do
   ##Terminating unamed vms
     aws ec2 terminate-instances --output text --instance-ids=$un_vm --region=$loc | tee -a $LOG
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
     		aws ec2 terminate-instances --output text --instance-ids=$all_vm --region=$region | tee -a $LOG
   	done

}

function monitor_region
{
	region=$1
	echo "State    Size        Name"
	aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Name,InstanceType,Tags[?Key==`Name`].Value | [0]]' --output text  --region=$region | grep -E -v 'terminated'
	echo "TOTAL VMS: " `aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Name,Tags[?Key=='Name'].Value | [0]]' --output text  --region=$region | grep -E -v 'terminated' | wc -l`
	echo "LARGE VMS: " `aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Name,InstanceType]' --output text  --region=$region | grep -E -v 'terminated' | grep 'large' | wc -l `
	echo "TOTAL SECURITY GROUPS " `aws ec2 describe-security-groups --region=$region --output text --query 'SecurityGroups[*].[GroupName]' | wc -l`	
}
function del_sec_groups
{
	region=$1
	all_sec_groups=($(aws ec2 describe-security-groups --region=$region --output text --query 'SecurityGroups[*].[GroupName]' ))
        vm_sec_groups=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[SecurityGroups[*].[GroupName]]' --output text  --region=$region))
        unused_sec_groups=($(echo ${all_sec_groups[@]} ${vm_sec_groups[@]} | tr ' ' '\n' | sort | uniq -u ))
	for un_sg in "${unused_sec_groups[@]}"
        do
                #Terminating unamed vms
                echo $un_sg
                aws ec2 delete-security-group --group-name $un_sg --region=$region | tee -a $LOG
        done

}

function del_key_pairs_region
{
	region=$1
	all_key_pairs=($(aws ec2 describe-key-pairs  --query 'KeyPairs[*].[KeyName]'  --region=$region --output text  ))
	vm_key_pairs=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[State.Name,KeyName]' --output text  --region=$region | grep -E -v 'terminated' | awk '{ print $2 }' ))
	unused_key_pairs=($(echo ${all_key_pairs[@]} ${vm_key_pairs[@]} | tr ' ' '\n' | sort | uniq -u ))
	for un_kp in "${vm_key_pairs[@]}"
	do
   		#Terminating unamed vms
		echo $un_kp
     		aws ec2 delete-key-pair --key-name $un_kp --region=$region | tee -a $LOG
   	done


}


#del_all_un_vms
# Call getopt to validate the provided input.
options=$(getopt -o --long delete-all-vms:delete-key-pairs:delete-security-groups -- "$@")
[[ ! $1 ]] && {
	read -r -p "Delete orphan vms in all location(Y/N) " response
        response=${response,,}
        if [[ ! $response =~ ^(yes|y) ]]
        then
        	exit 1
        fi
 	echo 'Deleting orphan vms in all locations' | tee -a $LOG
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
	read -r -p "Delete all VMs in $1 (Y/N):" response
        response=${response,,}
        if [[ ! $response =~ ^(yes|y) ]]
        then
        	exit 1
        fi
  
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
		read -r -p "Delete unused key pairs in all location(Y/N): " response
		response=${response,,}	
		if [[ ! $response =~ ^(yes|y) ]]
		then
			exit 1
		fi
		for region in "${!locations[@]}"
		do
			echo "Deleting following key pairs in $region" | tee -a $LOG
			echo "+------------------------------------------------+" | tee -a $LOG
			del_key_pairs_region $region 
			echo "+------------------------------------------------+" | tee -a $LOG
		done
	else
		 read -r -p "Delete unused key pairs in $1 (Y/N): " response
                response=${response,,}
                if [[ ! $response =~ ^(yes|y) ]]
                then
                        exit 1
                fi

  		region=$1
	        echo "Deleting following key pairs in $region" | tee -a $LOG
                echo "+------------------------------------------------+" | tee -a $LOG
                del_key_pairs_region $region
                echo "+------------------------------------------------+" | tee -a $LOG

	fi
	;;
   --delete-security-groups)
	if check_pass; then
        exit 1
        fi
	shift;
	if [ -z $1 ]
        then
                read -r -p "Delete unused security groups in all location(Y/N): " response
                response=${response,,}
                if [[ ! $response =~ ^(yes|y) ]]
                then
                        exit 1
                fi
                for region in "${!locations[@]}"
                do
                        echo "Deleting following security groups in $region" | tee -a $LOG
                        echo "+------------------------------------------------+" | tee -a $LOG
                        del_sec_groups $region
                        echo "+------------------------------------------------+" | tee -a $LOG
                done
        else
		 read -r -p "Delete unused security groups in $1 (Y/N): " response
                response=${response,,}
                if [[ ! $response =~ ^(yes|y) ]]
                then
                        exit 1
                fi

                region=$1
                echo "Deleting following security groups in $region" | tee -a $LOG
                echo "+------------------------------------------------+" | tee -a $LOG
                del_sec_groups $region
                echo "+------------------------------------------------+" | tee -a $LOG

        fi

	;;
   --monitor)
	shift;
	if [ -z $1 ]
        then
	for region in "${!locations[@]}"
        do
		echo "-------Total Instances on "${locations[$region]} "----------------"
		monitor_region $region	
	done
	else
		echo "-------Total Instances on "${locations[$1]} "-------------------"	
		monitor_region $1
	fi
	;;
   -h|--help|--info)
	man aws-ranger
	;;    
   --regions|--region)
	echo "Following are the various regions provided by AWS"
	divider===============================
	divider=$divider$divider

	header="\n %-30s %15s\n"
	format=" %-30s %15s\n"

	width=50

	printf "$header" "Region Name" "Region ID" 
	printf "%$width.${width}s\n" "$divider"

	printf "$format" \
	'US East (N. Virginia)' us-east-1 \
	'US West (N. California)' us-west-1 \
	'US West (Oregon)' us-west-2 \
	'Asia Pacific (Mumbai)' ap-south-1 \
	'Asia Pacific (Seoul)' ap-northeast-2 \
	'Asia Pacific (Singapore)' ap-southeast-1 \
	'Asia Pacific (Sydney)' ap-southeast-2 \
	'Asia Pacific (Tokyo)' ap-northeast-1 \
	'EU (Frankfurt)' eu-central-1 \
	'EU (Ireland)' eu-west-1 \
	'South America (Sau Paulo)' sa-east-1
	;;
   esac
    shift
done

