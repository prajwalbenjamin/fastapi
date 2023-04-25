#!/bin/bash

# Define Environment for our labs

function setlab() {
  az account set --subscription f3e03797-77f9-4fe3-b659-cd072361b4fc

  if [[ $LAB == "lab000151" ]]; then
    INGRESS="myjenkins"
    BDCURL="jenkins-poc-bsgh.boschdevcloud.com"
    APPID="785b8559-5d97-40da-8de2-c1def66b9e44"
    APPSEC="{{ APP_SEC }}"
    user="bdc2re" 
  elif [[ $LAB == "lab000167" ]]; then
    INGRESS="myingress"
    BDCURL="aks-poc-bsh.boschdevcloud.com"
    APPID="785b8559-5d97-40da-8de2-c1def66b9e44"
    APPSEC="{{ APP_SEC }}"
    user="bdc2re"
  elif [[ $LAB == "lab000218" ]];  then
    INGRESS="aks-lab000218"
    BDCURL="aks-lab000218.boschdevcloud.com"
    APPID="b8cd91f4-e35e-408f-889c-53f1314193d5"
    APPSEC="{{ APP_SEC }}"
    user="bdc2re"
  else
    echo "unknown Lab! please use lab000151 or lab000167 or lab000218"
    exit 1
  fi
  ACRURL="${LAB}acr.azurecr.io"
  az aks get-credentials --resource-group ${LAB}-rg --name $LAB
}

# Define usage Function

function usage() {
  echo "Usage: sudo $0 [-f] | [-d|--dryrun] | -n|--name <name> | [-h|--help]"
  echo "Options:"
  echo "  -n|--name <name>"
  echo "    Specify your desired name of jenkins; may not start with -"
  echo "  -f, --force"
  echo "     Remove github repo instead of appending '-archive' to its name"
  echo "  -d, --dryrun"
  echo "    No changes (except local) but show everything that would take place (use twice for more output)"
  echo "  -l, --lab"
  echo "    Specify your desired lab to deploy your jenkins (lab000151 | lab000167 | lab000218)"
  echo "  -h, --help  Show this help"
}

# Define Ingress

updateIngress() {
  kubectl -oyaml get ingress $INGRESS > jenkins-ingress.yaml 

  if [[ $(cat jenkins-ingress.yaml | grep "\/$CNAME\/") ]]; then 
    echo "Removing Ingress Configuration"
    # See deploy for content removed

    # Remove [-4,+1]-block around $CNAME
    tac jenkins-ingress.yaml | sed -e "/: \/$CNAME\//{n;N;N;N;N;d}" | tac > jenkins-ingress-post.yaml
    sed -i "/\/$CNAME\//,+1 d" jenkins-ingress-post.yaml
    if [[ "$DRYRUN" -ge "1" ]]; then
      echo ">>> kubectl apply -f jenkins-ingress-post.yaml"
      if [[ "$DRYRUN" -ge "2" ]]; then
        cat jenkins-ingress-post.yaml
      fi
      rm -rf jenkins-ingress*.yaml
    else
      kubectl apply -f jenkins-ingress-post.yaml
      rm -rf jenkins-ingress*.yaml
    fi
  else
    echo "Name already removed from Ingress"
    rm -rf jenkins-ingress*.yaml
  fi
}

# Define Authentication Redirect

updateAuthRedirect() {
  # Get existing redirect uris
  az ad app show --id $APPID -o json | jq -r ".web.redirectUris" > uris.json

  # Check is name is already present
  if [[ $(cat uris.json | grep "\/$CNAME\/") ]]; then
    echo "Removing Redirect Uri"
    # Modify url strings
    tr -d ",\"" < uris.json | sed "1d;$ d" > uris.json2; mv uris.json2 uris.json
    sed -i "/$CNAME/d" uris.json
    LIST=""
    while read line; do LIST+="$line "; done < uris.json
    if [[ "$DRYRUN" -eq "1" ]]; then
      echo ">>> az ad app update --id $APPID --web-redirect-uris $LIST"
      rm -rf uris.json*
    else
      az ad app update --id $APPID --web-redirect-uris $LIST
      rm -rf uris.json*
    fi
  else
    echo "Redirect Uri already removed"
    rm -rf uris.json*
  fi
}

# Define Credential pulling
function getCredentials() {
echo ""
echo "###################################################################"
echo " Please provide credentials to fetch Passwords from vault.bshg.com"
echo "###################################################################"
echo ""
echo "enter your username"

read  username

echo ""
echo "enter Password"
read -s password
echo ""

generate_post_data()
{
cat <<EOF
{
 "password": "$password"
}
EOF
}

echo "getting your token from the vault"

CLIENT_TOKEN=$(curl -s -H "X-Vault-Request: true" -H "Content-Type: application/json" --request POST --data "$(generate_post_data)" https://vault.esc.bshg.com/v1/auth/ldap/login/$username | awk -v FPAT='client_token[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)

#echo $CLIENT_TOKEN

if [[ $CLIENT_TOKEN == "" ]]; then
echo $CLIENT_TOKEN
echo "No Token returned! Did you provide the right Credentials?"
exit 1
fi


APP_SEC=""
GIT_INT_TOKEN=""
GIT_BDC_TOKEN=""

#### Getting Credentials #####

echo "getting github-bshg Access Token"
 
GITHUB_BDC_TOKEN=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/users/functional/$user \
| awk -v FPAT='github-bshg-token[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
#echo $GITHUB_BDC_TOKEN
echo $GITHUB_BDC_TOKEN > ~/token.txt

if [[ $GITHUB_BDC_TOKEN == "" ]]; then
echo "No Github Token returned! Do you have Access to that Secret?"
exit 1
fi

echo "internal github Access Token"

GITHUB_INT_TOKEN=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/app-instance/esc \
| awk -v FPAT='github-api-token[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
#echo $GITHUB_INT_TOKEN
if [[ $GITHUB_INT_TOKEN == "" ]]; then
echo "No internal Github Token returned! Do you have Access to that Secret?"
exit 1
fi


echo "getting Application Secrets"

if [[ $LAB == "lab000167" ]]; then

APP_SEC=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/jenkins-poc-bsgh \
| awk -v FPAT='secret[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
#echo $APP_SEC
    if [[ $APP_SEC == "" ]]; then
    echo "No APP Secret returned! Do you have Access to that Secret?"
    exit 1
    fi
elif [[ $LAB == "lab000218" ]]; then
APP_SEC=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/jenkins-prod-218 \
| awk -v FPAT='secret[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
#echo $APP_SEC
    if [[ $APP_SEC == "" ]]; then
    echo "No APP Secret returned! Do you have Access to that Secret?"
    exit 1
    fi
elif [[ $LAB == "lab000151" ]]; then
APP_SEC=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/jenkins-poc-bsgh \
| awk -v FPAT='secret[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
#echo $APP_SEC
    if [[ $APP_SEC == "" ]]; then
    echo "No APP Secret returned! Do you have Access to that Secret?"
    exit 1
    fi
else
echo "something went wrong, check the logs!"
exit 1
fi

echo "all necessary Credentials are fetched from vault" 
}


########################################## 
# MAIN Section
##########################################

# Credential setting; only use tokens and should come from vault or
# secure settings in github.  Internal & BDC Github needed currently.
user=""
useri=bsh-ci-esc
DRYRUN=0
FORCE=0

echo "#########################################################"
echo "###                                                   ###"
echo "###   Undeploy Jenkins from Bosch Development Cloud   ###"
echo "###                                                   ###"
echo "#########################################################"

while [[ $# -gt 0 ]]; do
  case $1 in
    -n | --name ) CNAME=$2; shift; shift;;
    -h | --help ) usage; exit 0;;
    -f | --force ) FORCE=1; shift;;
    -d | --dryrun ) DRYRUN=$((DRYRUN+1)); shift;;
    -l | --lab ) LAB=$2; setlab; shift; shift;;
    *) echo "Unknown argument $1"; exit 4;;
  esac;
done

getCredentials


# Check for Aguments. Ensure that Name and Lab are set
echo "CNAME=$CNAME"
echo "LAB=$LAB"
if [[ "$CNAME" == "" ]] || [[ "$LAB" == "" ]]; then
    echo "Name or Lab missing"
    usage
    exit 3
fi

if [[ $(curl -s -H "Authorization: token $GITHUB_BDC_TOKEN" https://github-bshg.boschdevcloud.com/api/v3/search/repositories?q=org:devops | grep "\"full_name\": \"devops/$CNAME\"") ]]; then
  echo "Repository exists"
  if [[ "$DRYRUN" -ge "1" ]]; then
    if [[ "$FORCE" -eq "1" ]]; then
      echo ">>> curl -s -H \"Authorization: token GITHUB_BDC_TOKEN\" -X DELETE https://github-bshg.boschdevcloud.com/api/v3/orgs/devops/repos/$CNAME"
    else
      echo ">>> curl -s -H \"Authorization: token $GITHUB_BDC_TOKEN\" -X PATCH -d '{\"name\":\""$CNAME-archive"\"}' https://github-bshg.boschdevcloud.com/api/v3/orgs/devops/repos/$CNAME"
    fi
    echo ">>> helm uninstall $CNAME"
  else
    if [[ "$FORCE" -eq "1" ]]; then
      curl -s -H "Authorization: token $GITHUB_BDC_TOKEN" -X DELETE https://github-bshg.boschdevcloud.com/api/v3/repos/devops/$CNAME
    else
      curl -s -H "Authorization: token $GITHUB_BDC_TOKEN" -X PATCH -d '{"name":"'"$CNAME-archive"'"}' https://github-bshg.boschdevcloud.com/api/v3/repos/devops/$CNAME
    fi
    # if $CNAME is already uninstalled, you get an error here - script should continue
    helm uninstall $CNAME
  fi
else
  echo "Repository already removed!"
fi

updateAuthRedirect
updateIngress