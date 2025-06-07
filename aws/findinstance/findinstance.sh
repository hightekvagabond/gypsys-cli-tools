#!/bin/bash

#this script figures out what profile(account) has the instance I'm looking for

# The instance name you're looking for
INSTANCE_NAME="ec2-34-222-138-181.us-west-2.compute.amazonaws.com"

# List all profiles
PROFILES=$(aws configure list-profiles)

# Loop through each profile
for PROFILE in $PROFILES; do
    echo "Checking profile: $PROFILE"
    
    # Check if a default region is set for the profile
    REGION=$(aws configure get region --profile $PROFILE)
    if [ -z "$REGION" ]; then
        # Set a default region if not already set
        REGION="us-west-2" # Replace with your preferred default region
        aws configure set region $REGION --profile $PROFILE
    fi
    
    # Get all regions
    REGIONS=$(aws ec2 describe-regions --profile $PROFILE --query 'Regions[].RegionName' --output text)
    
    # Loop through each region
    for REGION in $REGIONS; do
        echo "Checking region: $REGION"
        
        # Use the profile and region to list all EC2 instances
        INSTANCES=$(aws ec2 describe-instances --profile $PROFILE --region $REGION --query 'Reservations[].Instances[].InstanceId' --output text)
        
        # Loop through each instance
        for INSTANCE in $INSTANCES; do
            # Get the instance's public DNS name
            INSTANCE_DNS=$(aws ec2 describe-instances --instance-ids $INSTANCE --profile $PROFILE --region $REGION --query 'Reservations[].Instances[].PublicDnsName' --output text)
            
            # Check if the instance's DNS name matches the one you're looking for
            if [ "$INSTANCE_DNS" == "$INSTANCE_NAME" ]; then
                echo "Found the instance in profile: $PROFILE, region: $REGION"
                break 3
            fi
        done
    done
done

