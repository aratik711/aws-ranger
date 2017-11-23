#!/bin/bash

##Define the regions in aws
declare -A locations=( ["us-east-1"]="Virginia" ["us-west-1"]="California" ["us-west-2"]="Oregon" ["ap-south-1"]="Mumbai" ["ap-northeast-2"]="Seoul" ["ap-southeast-1"]="Singapore" ["ap-southeast-2"]="Sydney" ["ap-northeast-1"]="Tokyo" ["eu-central-1"]="Frankfurt" ["eu-west-1"]="Ireland" ["sa-east-1"]="Sau Paulo"  ["us-east-2"]="Ohio" ["eu-west-2"]="London" )

export AWS_ACCESS_KEY_ID={Your access key}
export AWS_SECRET_ACCESS_KEY={Your secret key}


#LOG="/home/compose/log/aws-ranger.log"

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
 for loc in "${!locations[@]}"
 do
  echo "---------Location: ${locations[$loc]}-----------"
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

##Delete all the VMs in one region
function del_all_vms_region
{
	region=$1
	## Get all Instance IDs for one region
	all_vms=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[State.Name,InstanceId,Tags[?Key==`Name`].Value | [0]]' --output text  --region=$region | grep -E -v 'terminated' | awk '{ print $2 }'))
	for all_vm in "${all_vms[@]}"
   	do
   	##Terminating vms one by one
     		aws ec2 terminate-instances --output text --instance-ids=$all_vm --region=$region 
   	done

}
## Monitor AWS 
function monitor_region
{
	region=$1
	echo "State    Size        Name"
	##Display list of all machines with state and size
	aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Name,InstanceType,Tags[?Key==`Name`].Value | [0]]' --output text  --region=$region | grep -E -v 'terminated'
	##Display count of machines
	echo "TOTAL VMS: " `aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Name,Tags[?Key=='Name'].Value | [0]]' --output text  --region=$region | grep -E -v 'terminated' | wc -l`
	##Display count of large machines
	echo "LARGE VMS: " `aws ec2 describe-instances --query 'Reservations[*].Instances[*].[State.Name,InstanceType]' --output text  --region=$region | grep -E -v 'terminated' | grep 'large' | wc -l `
	##Display count of security groups
	echo "TOTAL SECURITY GROUPS " `aws ec2 describe-security-groups --region=$region --output text --query 'SecurityGroups[*].[GroupName]' | wc -l`	

	echo "TOTAL KEY PAIRS " `aws ec2 describe-key-pairs --region=$region --output text --query 'KeyPairs[*].[KeyName]' | wc -l`	
}

##Delete unused security groups
function del_sec_groups
{
	region=$1
	##Get all security groups
	all_sec_groups=($(aws ec2 describe-security-groups --region=$region --output text --query 'SecurityGroups[*].[GroupName]' | grep 'jclouds#brooklyn-'))
	##Get used security groups
        vm_sec_groups=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[SecurityGroups[*].[GroupName]]' --output text  --region=$region | grep 'jclouds#brooklyn-'))
	##Get unused security groups
        unused_sec_groups=($(echo ${all_sec_groups[@]} ${vm_sec_groups[@]} | tr ' ' '\n' | sort | uniq -u ))
	for un_sg in "${unused_sec_groups[@]}"
        do
                #Terminating unamed security groups
                echo $un_sg
                aws ec2 delete-security-group --group-name $un_sg --region=$region 
        done

}

function poweroff_vms
{
	region=$1
	##Get all running vms
	vm_ids=($(aws ec2 describe-instances --region $region --query 'Reservations[*].Instances[*]. [State.Name,InstanceId,Tags[?Key==`Name`].Value | [0],Tags[?Key==`Opt Out`].Value | [0],Tags[?Key==`opt out`].Value | [0], Tags[?Key==`OptOut`].Value | [0], Tags[?Key==`optout`].Value | [0], Tags[?Key==`Opt out`].Value | [0]]' --output text | grep -E -v  'brooklyn-' | grep -E -v 'true|True|TRUE'| grep -E -v 'CloudAcademy|COE|Training' | grep 'running' | awk '{ print $2 }'))
	for vm_id in "${vm_ids[@]}"
	do
		##Stop running vms
		echo $vm_id
		aws ec2 stop-instances --instance-ids $vm_id --region $region
	done

}

function del_eip
{
        region=$1
        ##Get allocation Ids
        alloc_ids=($(aws ec2 describe-addresses --region $region --query 'Addresses[*].[AllocationId,PrivateIpAddress]' --output text | grep 'None' | awk '{ print $1 }'))
        for alloc_id in "${alloc_ids[@]}"
        do
                ##delete unused elastic IPs
                echo $alloc_id
                aws ec2 release-address --allocation-id $alloc_id --region $region
        done

}


function del_un_vols
{
	region=$1
	##Get all unused volumes
	vol_ids=($(aws ec2 describe-volumes --query 'Volumes[*].[VolumeId,State,Tags[?Key==`Opt out`].Value | [0], Tags[?Key==`Opt Out`].Value | [0],Tags[?Key==`opt out`].Value | [0], Tags[?Key==`OptOut`].Value | [0], Tags[?Key==`optout`].Value | [0]]' --output text --region $region | grep 'available' | grep -E -v 'true|True|TRUE' | awk '{print $1}'))
	for vol_id in "${vol_ids[@]}"
	do
		##Delete unused volumes
		echo $vol_id
		aws ec2 delete-volume --volume-id $vol_id --region $region
	done

}


function get_ami
{
	region=$1
	declare -A regex_arr=( ["Windows_Server-2012-R2_RTM-English-64Bit-Base"]="Windows 2012" ["Windows_Server-2008-R2_SP1-English-64Bit-Base"]="Windows 2008 Community" ["Windows_Server-2008-R2_SP1-English-64Bit-SQL_2012_SP2_Express"]="Windows 2008 Marketplace" ["apache24-ubuntu1604-hvm"]="Ubuntu 16.04" ["ubuntu/images/ebs-ssd/ubuntu-trusty-14.04-amd64-server"]="Ubuntu 16.04" ["RightImage_RHEL_6.3_x64"]="RHEL 6.3" ["cb-centos72-amb212"]="Centos 7.2" ["suse-sles-11-sp3"]="SUSE" )
	#declare -A array

	#while read id value; do
        #	array[$id]=$value
	#done <(aws ec2 describe-images --region $region --query 'Images[*].[Name,ImageId]' --output text)

	##get ami for various OS
	for regex in "${!regex_arr[@]}"
        do
		#for arr in "${!array[@]}"
		#do
		#	if [[ $arr == *"$regex"* ]]
		#	echo "Regex: ${regex_arr[$regex]} AMI ID: ${array[$arr]}"
		#	fi
		#done
		echo "${regex_arr[$regex]}: "
		aws ec2 describe-images --region $region --query 'Images[*].[Name,ImageId]' --output text | grep "$regex" | awk 'NR==1'| awk '{print $2}'	
	done
}

##Delete unused key pairs
function del_key_pairs_region
{
	region=$1
	## Get all key pairs
	all_key_pairs=($(aws ec2 describe-key-pairs  --query 'KeyPairs[*].[KeyName]'  --region=$region --output text  | grep 'jclouds#brooklyn-'))
	## Get used key pairs
	vm_key_pairs=($(aws ec2 describe-instances  --query 'Reservations[*].Instances[*].[State.Name,KeyName]' --output text  --region=$region | grep -E -v 'terminated' | awk '{ print $2 }' | grep 'jclouds#brooklyn-'))
	##Get unused key pairs
	unused_key_pairs=($(echo ${all_key_pairs[@]} ${vm_key_pairs[@]} | tr ' ' '\n' | sort | uniq -u ))
	for un_kp in "${unused_key_pairs[@]}"
	do
   		#Terminating unused key pairs
		echo $un_kp
     		aws ec2 delete-key-pair --key-name $un_kp --region=$region 
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
	##if check_pass; then
        ##exit 1
        ##fi
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
			echo "Deleting following key pairs in ${locations[$region]}" 
			echo "+------------------------------------------------+" 
			del_key_pairs_region $region 
			echo "+------------------------------------------------+" 
		done
	else
		 read -r -p "Delete unused key pairs in $1 (Y/N): " response
                response=${response,,}
                if [[ ! $response =~ ^(yes|y) ]]
                then
                        exit 1
                fi

  		region=$1
	        echo "Deleting following key pairs in ${locations[$region]}" 
                echo "+------------------------------------------------+" 
                del_key_pairs_region $region
                echo "+------------------------------------------------+"  

	fi
	;;
   --delete-security-groups)
	##if check_pass; then
        ##exit 1
        ##fi
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
                        echo "Deleting following security groups in ${locations[$region]}"  
                        echo "+------------------------------------------------+" 
                        del_sec_groups $region
                        echo "+------------------------------------------------+" 
                done
        else
		 read -r -p "Delete unused security groups in $1 (Y/N): " response
                response=${response,,}
                if [[ ! $response =~ ^(yes|y) ]]
                then
                        exit 1
                fi

                region=$1
                echo "Deleting following security groups in ${locations[$region]}" 
                echo "+------------------------------------------------+" 
                del_sec_groups $region
                echo "+------------------------------------------------+" 

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
   --poweroff)
	shift;
	if [ -z $1 ]
        then
	for region in "${!locations[@]}"
        do
		echo "-------Shutting down Instances on "${locations[$region]} "----------------"
		poweroff_vms $region	
	done
	else
		echo "-------Shutting down Instances on "${locations[$1]} "-------------------"	
		poweroff_vms $1
	fi
	;;
   --delete-volumes)
	shift;
	if [ -z $1 ]
        then
	for region in "${!locations[@]}"
        do
		echo "-------Deleting volumes on "${locations[$region]} "----------------"
		del_un_vols $region	
	done
	else
		echo "-------Deleting volumes on "${locations[$1]} "-------------------"	
		del_un_vols $1
	fi
	;;
   --delete-eip)
        shift;
        if [ -z $1 ]
        then
        for region in "${!locations[@]}"
        do
                echo "-------Deleting Elastic IPs on "${locations[$region]} "----------------"
                del_eip $region
        done
        else
                echo "-------Deleting Elastic IPs on "${locations[$1]} "-------------------"
                del_eip $1
        fi
        ;;

   --get-ami)
        shift;
        if [ -z $1 ]
        then
        for region in "${!locations[@]}"
        do
                echo "-------AMI Id of  "${locations[$region]} "----------------"
                get_ami $region
        done
        else
                echo "-------AMI Id of  "${locations[$1]} "-------------------"
                get_ami $1
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
	'US East (Ohio)' us-east-2 \
	'EU (London)' eu-west-2 \
	'South America (Sau Paulo)' sa-east-1
	;;
   esac
    shift
done
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
exit 0;
