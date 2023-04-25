#!/bin/bash -x

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
  echo "Usage: sudo $0 [-d|--dryrun] | -n|--name <name> | [-h|--help] | --id user:password"
  echo "Options:"
  echo "  -n|--name <name>"
  echo "    Specify your desired name of jenkins; may not start with -"
  echo "  -d, --dryrun"
  echo "    No changes (except local) but show everything that would take place (use twice for more output)"
  echo "  -l, --lab"
  echo "    Specify your desired lab to deploy your jenkins (lab000151 | lab000167 | lab000218)"
  echo "  -h, --help  Show this help"
  echo "  --id <user:password>"
  echo "    This is your personal account used to access the vault. Without this, you will be queried"
}

# Define Ingress

function updateIngress() {
  kubectl -oyaml get ingress $INGRESS > jenkins-ingress.yaml 

  if [[ $(cat jenkins-ingress.yaml | grep "\/$CNAME\/") ]]; then 
    echo "Name already set in Ingress"
  else
    echo "adding Ingress Configuration"

    # heredoc for append
    read -d '' append <<eof
    \# correct indentation (important) for heredoc
      - backend:
          service:
            name: $CNAME-jenkins
            port:
              number: 80
        path: /$CNAME/
        pathType: ImplementationSpecific
eof

    # Remove last two lines, probably should remove all of "status:"
    tac jenkins-ingress.yaml | sed '1,2 d' | tac > jenkins-ingress-post.yaml

    echo "$append" >> jenkins-ingress-post.yaml

    if [[ "$DRYRUN" -ge "1" ]]; then
      echo ">>> kubectl apply -f jenkins-ingress-post.yaml"
      if [[ "$DRYRUN" -ge "2" ]]; then
        cat jenkins-ingress-post.yaml
      fi
      sleep 5
      rm -rf jenkins-ingress*.yaml
    else
      kubectl apply -f jenkins-ingress-post.yaml
      sleep 5
      rm -rf jenkins-ingress*.yaml
    fi
  fi
}

# Define Authentication Redirect

function updateAuthRedirect() {
  # Get existing redirect uris
  az ad app show --id $APPID -o json | jq -r ".web.redirectUris" > uris.json

  # Check is name is already present
  if [[ $(cat uris.json | grep "\/$CNAME\/") ]]; then
    echo "Redirect Uri already exists"
  else
    echo "Adding Redirect Uri"
    # Modify url strings
    tr -d ",\"" < uris.json | sed "1d;$ d" > uris.json2; mv uris.json2 uris.json
    echo "  https://$BDCURL/$CNAME/securityRealm/finishLogin" >> uris.json
    LIST=""
    while read line; do LIST+="$line "; done < uris.json
    if [[ "$DRYRUN" -ge "1" ]]; then
      echo ">>> az ad app update --id $APPID --web-redirect-uris $LIST"
      rm -rf uris.json*
    else
      az ad app update --id $APPID --web-redirect-uris $LIST
      rm -rf uris.json*
    fi
  fi
}

# Define Credential pulling
function getCredentials() {
  if [[ $USERPASS == "" ]]; then
    echo ""
    echo "###################################################################"
    echo " Please provide credentials to fetch Passwords from vault.bshg.com"
    echo "###################################################################"
    echo ""
    echo "Enter your username"

    read  username

    echo ""
    echo "Enter password"
    read -s password
  else
    # Poor man's split - no colons in passwords allowed
    username=$(echo $USERPASS | sed -e "s/:.*//")
    password=$(echo $USERPASS | sed -e "s/.*://")
  fi

  echo "Getting your token from the vault"

  CLIENT_TOKEN=$(curl -s -H "X-Vault-Request: true" -H "Content-Type: application/json" --request POST --data "{\"password\": \"$password\"}" https://vault.esc.bshg.com/v1/auth/ldap/login/$username | awk -v FPAT='client_token[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)

  if [[ $CLIENT_TOKEN == "" ]]; then
    echo "No Token returned! Did you provide the right Credentials?"
    exit 1
  fi

  APP_SEC=""
  GIT_INT_TOKEN=""
  GIT_BDC_TOKEN=""
  SPLUNK_CLOUD_TOKEN=""

  # Getting Credentials

  echo "Get github-bshg Access Token"
 
  GITHUB_BDC_TOKEN=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/users/functional/$user \
    | awk -v FPAT='github-bshg-token[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
  if [[ $GITHUB_BDC_TOKEN == "" ]]; then
    echo "No Github Token returned! Do you have Access to that Secret?"
    exit 1
  fi

  echo "Get internal Github Access Token"

  GITHUB_INT_TOKEN=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/app-instance/esc \
    | awk -v FPAT='github-api-token[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
  if [[ $GITHUB_INT_TOKEN == "" ]]; then
    echo "No internal Github Token returned! Do you have Access to that Secret?"
    exit 1
  fi

  SPLUNK_CLOUD_TOKEN=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/splunk \
    | awk -v FPAT='hec_token@awf-01.splunkcloud.com[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
  if [[ $SPLUNK_CLOUD_TOKEN == "" ]]; then
    echo "No Splunk Cloud Token returned! Do you have Access to that Secret?"
    exit 1
  fi

  echo "Get Application Secrets"

  if [[ $LAB == "lab000167" ]]; then
    APP_SEC=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/jenkins-poc-bsgh \
      | awk -v FPAT='secret[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
    if [[ $APP_SEC == "" ]]; then
      echo "No APP Secret returned! Do you have Access to that Secret?"
      exit 1
    fi
  elif [[ $LAB == "lab000218" ]]; then
    APP_SEC=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/jenkins-prod-218 \
      | awk -v FPAT='secret[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
    if [[ $APP_SEC == "" ]]; then
      echo "No APP Secret returned! Do you have Access to that Secret?"
      exit 1
    fi
  elif [[ $LAB == "lab000151" ]]; then
    APP_SEC=$(curl -s -H "X-Vault-Token: $CLIENT_TOKEN" -X GET https://vault.esc.bshg.com/v1/application/data/jenkins/bdc/jenkins-poc-bsgh \
      | awk -v FPAT='secret[^[:space:]]+' 'NF{ print $1 }' | cut -d "," -f1 | cut -d "\"" -f3)
    if [[ $APP_SEC == "" ]]; then
      echo "No APP Secret returned! Do you have Access to that Secret?"
      exit 1
    fi
  else
    echo "Something went wrong, check the logs!"
    exit 1
  fi

  echo "All necessary Credentials were fetched from vault" 
}

# We should probably do this with json and python by now. Programming
# logic is quite difficult with bash and yaml! But rebuild everything?
# Maybe extrat this part as a )local python script?
  
function getConnectivityMatrix {
  echo "Get matrix"

  # Find existing clusters / credentials in the existing deployment.
  exClusters=$(grep -E -- '- kubernetes|\sname:' $1 | sed -n '/kubernetes/{n;p;}' | sed 's/.*name: "\(.*\)"/\1/')
  exCreds=$(grep -E -- '- certificate|\sid:' $1 | sed -n '/certificate/{n;p;}' | sed 's/.*id: "\(.*\)"/\1/')

  # Find intended clusters
  rm -rf assets
  git clone https://${useri}:${GITHUB_INT_TOKEN}@production.github.bshg.com/System-Ops/Assets.git assets
  pushd assets;
  # This gives you line with the jenkins, jlab, cluster, cllab.
  inClusters=$(grep "$CNAME,$LAB" Jenkins-K8s.csv)

  for i in $inClusters; do
    cl=$(echo $i | cut -d ',' -f 3)
    if echo $exClusters | grep -q $cl; then
      echo "K8s cluster $cl already made explicit"
    else
      # Create a new section like "-kubernetes ..." for those missing in existing deployment
      read -d '' appCluster <<eof
        \# correct indentation (important) for heredoc
        - kubernetes:
            credentialsId: "${cl}-cred"
            name: "$cl"
            namespace: "jenkins"
            skipTlsVerify: true
            webSocket: true
eof
      echo "$appCluster"
    fi
  done
  for i in $inClusters; do
    cl=$(echo $i | cut -d ',' -f 3)
    if echo $exCreds | grep -q ${cl}-cred; then
      echo "Credential ${cl}-cred already made explicit"
    else
      # Create a new section like "-certificate ..." for those missing in existing deployment
      read -d '' appCred <<eof
              \# correct indentation (important) for heredoc
              - certificate:
                  description: "${cl}-cred"
                  id: "${cl}-cred"
                  scope: GLOBAL
                  keyStoreSource:
                    uploaded:
                      uploadedKeystore: |-
                        das-muss-aus-dem-keywault-gelesen-werden
eof
      echo "$appCred"
    fi
  done

  # Return to previous dir
  popd
  
  # TODO:
  # (1) Existing config should not be modified - rather removed by
  # people to be compatible with this redeployment.

  # (2) The new sections must be appended in the correct spots.

  # (3) The current script assumes that clusters and jenkinses are
  # unique across all labs, even though the csv looks differently.  If
  # this is inconvenient, we need to modify the script above to
  # include lab names.

  # (4) We should also create some tests - the current reality doesn't
  # cover potential cases. We can run these tests during deployment on
  # a fake csv & config. in/out = 0,1,2 clusters, same for creds = 18 TCs.
}

# Define Sanity test

function testJenkinsIsUp() {
  until [[ `curl -s -o /dev/null -w "%{http_code}" https://$BDCURL/$CNAME/` -eq "403" ]]; do
    echo "Trying to reach 403 at https://$BDCURL/$CNAME/ ..."
    sleep 10
  done
  echo "Connect attempt to https://$BDCURL/$CNAME/ successful!"
}

########################################## 
# MAIN Section
##########################################

# Credential setting; only use tokens and should come from vault or
# secure settings in github.  Internal & BDC Github needed currently.
#user=bdc2re
useri=bsh-ci-esc
DRYRUN=0

echo "#################################################"
echo "###                                           ###"
echo "### Deploy Jenkins in Bosch Development Cloud ###"
echo "###                                           ###"
echo "#################################################"

while [[ $# -gt 0 ]]; do
  case $1 in
    --id ) USERPASS=$2; shift; shift;;
    -n | --name ) CNAME=$2; shift; shift;;
    -h | --help ) usage; exit 0;;
    -d | --dryrun ) DRYRUN=$((DRYRUN+1)); shift;;
    -l | --lab ) LAB=$2; setlab; shift; shift;;
    *) echo "Unknown argument $1"; exit 4;;
  esac;
done

# Check for Aguments. Ensure that Name and Lab are set
echo "CNAME=$CNAME"
echo "LAB=$LAB"
if [[ "$CNAME" == "" ]] || [[ "$LAB" == "" ]]; then
    echo "Name or Lab missing"
    usage
    exit 3
fi

getCredentials

echo "Checking if configuration repo already exist"

helm repo add jenkins https://charts.jenkins.io

if [[ $(curl -s -H "Authorization: token $GITHUB_BDC_TOKEN" https://github-bshg.boschdevcloud.com/api/v3/search/repositories?q=org:devops | grep "\"full_name\": \"devops/$CNAME\"") ]]; then
  echo "Repository already exists"
  # Clone repo
  git clone  https://${user}:${GITHUB_BDC_TOKEN}@github-bshg.boschdevcloud.com/devops/$CNAME.git $CNAME
  # Check for yaml
  if [[ -e $CNAME/helm-values.yaml ]]; then

    ### insert Vault Values ###

    echo "set helm values"
    sed -i "s/{{ ACRURL }}/$ACRURL/g;s/{{ APPID }}/$APPID/g;s/{{ APPSEC }}/$APP_SEC/g" $CNAME/helm-values.yaml
    sed -i "s/{{ GIT_BDC_TOKEN }}/$GITHUB_BDC_TOKEN/g;s/{{ GIT_BDC_USER }}/$user/g" $CNAME/helm-values.yaml
    sed -i "s/{{ SPLUNK_CLOUD_TOKEN }}/$SPLUNK_CLOUD_TOKEN/g" $CNAME/helm-values.yaml

    # Stay in this dir
    pushd $CNAME; getConnectivityMatrix helm-values.yaml; popd

    echo "Config found, will apply changes"
    if [[ "$DRYRUN" -ge "1" ]]; then
      echo ">>> helm upgrade $CNAME -f $CNAME/helm-values.yaml jenkins/jenkins"
      if [[ "$DRYRUN" -ge "2" ]]; then
         echo "set helm values but will not print them in DRYRUN"
         cat $CNAME/helm-values.yaml
      fi
    else
      helm upgrade $CNAME -f $CNAME/helm-values.yaml jenkins/jenkins

      testJenkinsIsUp

      #cleanup repo
      echo "cleanup Deploy Directory"
      rm -rf $CNAME
    fi
  else
    echo "No config found! Will exit here"
    exit 5
  fi
else
  echo "Repository does not exist: creating it!"
  if [[ "$DRYRUN" -ge "1" ]]; then
    echo ">>> curl -u \"${user}:GTIHUB_BDC_TOKEN\" https://github-bshg.boschdevcloud.com/api/v3/orgs/devops/repos -d '{\"name\":\"'$CNAME'\",\"private\":true}' > /dev/null 2>&1"
    echo ">>> curl -X PUT -H \"Accept: application/vnd.github.v3+json\" -H \"Authorization: token GITHUB_BDC_TOKEN\" -d '{\"permission":"admin\"}' https://github-bshg.boschdevcloud.com/api/v3/orgs/devops/teams/alm/repos/devops/$CNAME > /dev/null 2>&1"
    echo ">>> git clone https://${user}:GITHUB_BDC_TOKEN@github-bshg.boschdevcloud.com/devops/$CNAME.git $CNAME"
    mkdir $CNAME
    git init $CNAME
  else
   # curl -s -u "${user}:${GITHUB_BDC_TOKEN}" https://github-bshg.boschdevcloud.com/api/v3/user/repos -d '{"name":"'$CNAME'","private":true}' > /dev/null 2>&1
   # git clone https://${user}:${cred_bdcgithub}@github-bshg.boschdevcloud.com/${user}/$CNAME.git $CNAME
     curl -u "${user}:${GITHUB_BDC_TOKEN}" https://github-bshg.boschdevcloud.com/api/v3/orgs/devops/repos -d '{"name":"'$CNAME'","private":true}' > /dev/null 2>&1
     curl -X PUT -H "Accept: application/vnd.github.v3+json" -H "Authorization: token ${GITHUB_BDC_TOKEN}" -d '{"permission":"admin"}' https://github-bshg.boschdevcloud.com/api/v3/orgs/devops/teams/alm/repos/devops/$CNAME > /dev/null 2>&1  
     mkdir $CNAME
     git clone https://${user}:${GITHUB_BDC_TOKEN}@github-bshg.boschdevcloud.com/devops/$CNAME.git $CNAME
  fi
  cd $CNAME
  echo "Get template"
  git clone  https://${useri}:${GITHUB_INT_TOKEN}@production.github.bshg.com/esc/bsh-jenkins-template.git $CNAME-template
  cp $CNAME-template/* ./
  rm -rf $CNAME-template
  git add -A
  echo "Modify template"
  sed -s -i "s/{{ CNAME }}/$CNAME/g" helm-values.yaml alljobs.groovy README.md
  sed -i "s/{{ BDCURL }}/$BDCURL/g" helm-values.yaml README.md
  sed -i "s/{{ ACRURL }}/$ACRURL/g;s/{{ APPID }}/$APPID/g;s/{{ APPSEC }}/$APP_SEC/g" helm-values.yaml
  sed -i "s/{{ GIT_BDC_TOKEN }}/$GITHUB_BDC_TOKEN/g;s/{{ GIT_BDC_USER }}/$user/g" helm-values.yaml
  sed -i "s/{{ SPLUNK_CLOUD_TOKEN }}/$SPLUNK_CLOUD_TOKEN/g" helm-values.yaml

  # Stay in this dir
  getConnectivityMatrix helm-values.yaml

  echo "Deploy via helm"
  # Parse the files from the template
  if [[ "$DRYRUN" -ge "1" ]]; then
    echo ">>> helm install $CNAME -n default -f helm-values.yaml jenkins/jenkins"
    if [[ "$DRYRUN" -ge "2" ]]; then
      cat helm-values.yaml
    fi
  else
    helm install $CNAME -n default -f helm-values.yaml jenkins/jenkins
  fi

  if [[ "$DRYRUN" -ge "1" ]]; then
    echo ">>> git push origin master"
  else
   ### remove credentials ###
   echo "remove credentials from file"
   sed -i "s/$APP_SEC/{{ APPSEC }}/g;s/$APPID/{{ APPID }}/g" helm-values.yaml
   sed -i "s/$GITHUB_BDC_TOKEN/{{ GIT_BDC_TOKEN }}/g;s/$user/{{ GIT_BDC_USER }}/g" helm-values.yaml
   sed -i "s/$SPLUNK_CLOUD_TOKEN/{{ SPLUNK_CLOUD_TOKEN }}/g" helm-values.yaml
   git commit -a -m "Adding files"
   echo "pushing repo"
   git push origin master
  fi

  updateAuthRedirect
  updateIngress
  testJenkinsIsUp
  #cleanup repo
    echo "cleanup Deploy Directory"
    rm -rf ../$CNAME/

fi