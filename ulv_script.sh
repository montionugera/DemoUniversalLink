#!/bin/bash -v

#set -euxo pipefail
# Instructions:
# 1. Save this Script as twig_script.sh to an easily accessible location
# 2. Open a terminal window at the location of the script
# 3. Run: bash twig_script.sh PATH_TO_PROJECT/PROJECT_NAME.xcodeproj
# Note that you must point the script at the xcode project itself, and not just the directory of the project.

#####################
#Get Project Filepath
#####################
pbxproject="$1"

#pbxProject File
folder="${pbxproject%/*}"
pbxproject="$pbxproject/project.pbxproj"
##############################
#variables this script returns
##############################
branch_app_domain="0"
branch_key="0"
bundleid="0"
teamid="0"
codesignEntitlements="0"
applinksString="0"
urlschemeString="0"
entitlementsIncluded=false
sizei=0
url_scheme=""
applinks=""

########################
#parsing pbxProject file
########################
bundleid="$(egrep --null -m 1 "PRODUCT_BUNDLE_IDENTIFIER" "$pbxproject" | awk -v FS='\=' '{print $2}')"
teamid="$(egrep --null -m 1 "DevelopmentTeam" "$pbxproject" | awk -v FS='\=' '{print $2}')"
plistfilePath="$(egrep --null -m 1 "INFOPLIST_FILE = .*/.*\.plist.*$" "$pbxproject" | awk -v FS='\=' '{print $2}')"
plistfilePath=$(echo ${plistfilePath%;})

#remove whitespaces, quotes and other clutter
plistfilePath="${plistfilePath%\;}"
plistfilePath="${plistfilePath%\"}"
plistfilePath="$(echo -e "${plistfilePath}" | tr -d '[[:space:]]')"
plistfilePath="${plistfilePath#\"}"

#get entitlements location
codesignEntitlements="$(egrep --null -m 1 "CODE_SIGN_ENTITLEMENTS = .*\.entitlements.*$" "$pbxproject" | awk -v FS='\=' '{print $2}')"

#remove whitespaces, quotes and other clutter
codesignEntitlements="${codesignEntitlements%\;}"
codesignEntitlements="${codesignEntitlements%\"}"
codesignEntitlements="$(echo -e "${codesignEntitlements}" | sed -e 's/^[[:space:]]*//')"
codesignEntitlements="${codesignEntitlements#\"}"
#Account for for variable paths (ex ${SRCROOT})
codesignEntitlements="${codesignEntitlements#\$*/}"
plistfilePath="${plistfilePath#\$*/}"
#Get the Info.plist File
plistFile="$folder/$plistfilePath"
########################
#parsing info.plist file
########################
branch_app_domain="$(egrep --null -A1 "<key>branch_app_domain</key>" "$plistFile" | grep -v "<key>branch_app_domain</key>")"
branch_key="$(egrep --null -A1 "branch_key" "$plistFile" | grep -v "<key>branch_key</key>")"
branch_key=$(echo $branch_key| grep '<string>'| awk -v FS='<string>|</string>' '{print $2}')
# Branch key Test for Unity
if [ "$branch_key" == "" ]
then
	if [ -d "$folder/Libraries/Plugins/Branch/iOS" ];
	then
		branch_key="$(egrep --null -m 1 "_branchKey" "$folder/Libraries/Plugins/Branch/iOS/BranchiOSWrapper.mm" | awk -v FS='\=' '{print $2}')"
		#remove whitespaces and quotes
		branch_key="${branch_key%;}"
		branch_key="$(echo -e "${branch_key}" | tr -d '[[:space:]]')"
		branch_key="${branch_key#@}"
		branch_key="${branch_key%\"}"
		branch_key="${branch_key#\"}"
	fi
fi
clear
#Handle multiple Branch keys
if [ "$branch_key" == "" ]
then
	echo "There may be multiple keys in this project. Do you want to validate the live(l) or test(t) configuration?"
	read key
	if [ "$key" = "l" ] || [ "$key" = "live" ]
	then
		echo "Live"
		branch_key="$(egrep --null -A1 "<key>live</key>" "$plistFile" | grep -v "<key>live</key>")"
	elif [ "$key" = "t" ] || [ "$key" = "test" ]
	then
		branch_key="$(egrep --null -A1 "<key>test</key>" "$plistFile" | grep -v "<key>test</key>")"
	fi
	branch_key=$(echo $branch_key| grep '<string>'| awk -v FS='<string>|</string>' '{print $2}')
fi
# Bundle id Test for Cordova/Ionic/Unity
if [ "$bundleid" == "" ]
then
  bundleid="$(egrep --null -A1 "<key>CFBundleIdentifier</key>" "$plistFile" | grep -v "<key>CFBundleIdentifier</key>" | awk -v FS='<string>|</string>' '{print $2}')"
  # Check if the bundle id has the product name
  if [[ "$bundleid" != "" && $bundleid == *"PRODUCT_NAME"* ]]
  then
	  product="$(egrep --null -m 1 "PRODUCT_NAME" "$pbxproject" | awk -v FS='\=' '{print $2}')"
	  product=$(echo ${product%;})
	  product="$(echo -e "${product}" | tr -d '[[:space:]]')"
	  product="${product%\"}"
	  product="${product#\"}"
	  bundleid="${bundleid%$\{PRODUCT_NAME\}}"
	  bundleid="$(echo "$bundleid$product")"
  fi
fi

while read -r line
do
# getting the branch url scheme
    if [ "$line" == "<key>CFBundleURLSchemes</key>" ];
	then
		read -r line
		if [ "$line" == "<array>" ];
		then
			read -r line
			while [ "$line" != "</array>" ];
			do
				url_scheme[$sizei]="$line"
				((sizei+=1))
				read -r line
			done
		else
			read -r line
			url_scheme[0]="$line"
		fi
    fi
done < "$plistFile"

######################
#santitize the strings
######################
branch_app_domain=$(echo $branch_app_domain| grep '<string>'| awk -v FS='<string>|</string>' '{print $2}')
bundleid=$(echo ${bundleid%;})
#remove whitespaces and quotes
bundleid="$(echo -e "${bundleid}" | tr -d '[[:space:]]')"
bundleid="${bundleid%\"}"
bundleid="${bundleid#\"}"
teamid=$(echo $teamid| awk -v FS=';' '{print $1}')
codesignEntitlementspath="$folder/$codesignEntitlements"
plistfilePath="$folder/$plistfilePath"
codesignEntitlements=$(echo $codesignEntitlements | awk -v FS="/" '{print $2}')

#check if entitlements file is included in the build project
codevalue=$(awk '/Begin\ PBXBuildFile\ section/{f=1;next} /End\ PBXBuildFile\ section/{f=0} f'  "$pbxproject")
#check if applinks are present in the entitlements file
applinksString=$(egrep "applinks*" "$codesignEntitlementspath");
if [ "$codevalue" == "" ] ; then
	entitlementsIncluded=false
else
	entitlementsIncluded=true
fi
# get url schemes
for (( i=0; i<$sizei; i++ ));
do
	 url_scheme[$i]=$(echo ${url_scheme[$i]}| grep '<string>'| awk -v FS='<string>|</string>' '{print $2}')
done
sizei=0
for appstring in $applinksString
do
	sizei+=1
	applinks[sizei]=$(echo $appstring | grep '<string>'| awk -v FS='<string>|</string>' '{print $2}')
done

applinksString="["
urlschemeString="["

#####################
# display the strings
#####################

for i  in "${url_scheme[@]}"
do
	urlschemeString="$urlschemeString"\\\""$i"\\\"","
#	echo $i
done
urlschemeString="${urlschemeString%,}]"

# get applinks schemes
for i  in "${applinks[@]}"
do
	applinksString="$applinksString "\\\""$i"\\\"","
#	echo $i
done
applinksString="${applinksString%,}]"
#Grow a tree. No reason why. It just looks nice, and because Branch. Thats all, have a nice day. Also, the status bar doesn't mean anything.
clear
echo -ne 'Growing....#                         (1%)\r';echo "";echo "";echo "";echo "";echo "";echo "";echo "";echo "";echo "";echo "";echo "     \/ ._\//_/__/  ,\_//_ _\/.  \_//__/_";sleep $(awk -v "seed=$[(RANDOM & 32767) + 32768 * (RANDOM & 32767)]" 'BEGIN { srand(seed); printf("%.5f\n", rand()) }');clear;echo -ne 'Growing....###                       (20%)\r';echo "";echo "";echo "";echo "";echo "";echo "";echo "";echo "";echo "       |o|        | |         | |";echo "       |.|        | |         | |";echo "     \/ ._\//_/__/  ,\_//_ _\/.  \_//__/_";sleep $(awk -v "seed=$[(RANDOM & 32767) + 32768 * (RANDOM & 32767)]" 'BEGIN { srand(seed); printf("%.5f\n", rand()) }');clear;echo -ne 'Growing....#####                     (33%)\r';echo "";echo "";echo "";echo "";echo "";echo "";echo "   %&&%/ %&%%&&@@\ V /@@'   88\8 /88";echo "    &%\   /%&     |.|        \  |8";echo "       |o|        | |         | |";echo "       |.|        | |         | |";echo "     \/ ._\//_/__/  ,\_//_ _\/.  \_//__/_";sleep $(awk -v "seed=$[(RANDOM & 32767) + 32768 * (RANDOM & 32767)]" 'BEGIN { srand(seed); printf("%.5f\n", rand()) }');clear;echo -ne 'Growing....#############             (66%)\r';echo "";echo "";echo "";echo "";echo "   ,%&\%&&%&&%,@@@\@@@/@@@88\88888/88";echo "   %&&%&%&/%&&%@@\@@/ /@@@88888\88888";echo "   %&&%/ %&%%&&@@\ V /@@'   88\8 /88";echo "    &%\   /%&     |.|        \  |8";echo "       |o|        | |         | |";echo "       |.|        | |         | |";echo "     \/ ._\//_/__/  ,\_//_ _\/.  \_//__/_";sleep $(awk -v "seed=$[(RANDOM & 32767) + 32768 * (RANDOM & 32767)]" 'BEGIN { srand(seed); printf("%.5f\n", rand()) }');clear;echo -ne 'Growing....###################       (80%)\r';echo "";echo "";echo "";echo "    ,&%%&%&&%,@@@@@/@@@@@@,8888\88/8o";echo "   ,%&\%&&%&&%,@@@\@@@/@@@88\88888/88";echo "   %&&%&%&/%&&%@@\@@/ /@@@88888\88888";echo "   %&&%/ %&%%&&@@\ V /@@'   88\8 /88";echo "    &%\   /%&     |.|        \  |8";echo "       |o|        | |         | |";echo "       |.|        | |         | |";echo "     \/ ._\//_/__/  ,\_//_ _\/.  \_//__/_";sleep $(awk -v "seed=$[(RANDOM & 32767) + 32768 * (RANDOM & 32767)]" 'BEGIN { srand(seed); printf("%.5f\n", rand()) }');clear;echo -ne 'Growing....#######################   (100%)\r\n';echo "               ,@@@@@@@,";echo "       ,,,.   ,@@@@@@/@@,  .oo8888o.";echo "    ,&%%&%&&%,@@@@@/@@@@@@,8888\88/8o";echo "   ,%&\%&&%&&%,@@@\@@@/@@@88\88888/88";echo "   %&&%&%&/%&&%@@\@@/ /@@@88888\88888";echo "   %&&%/ %&%%&&@@\ V /@@'   88\8 /88";echo "    &%\   /%&     |.|        \  |8";echo "       |o|        | |         | |";echo "       |.|        | |         | |";echo "     \/ ._\//_/__/  ,\_//_ _\/.  \_//__/_";sleep $(awk -v "seed=$[(RANDOM & 32767) + 32768 * (RANDOM & 32767)]" 'BEGIN { srand(seed); printf("%.5f\n", rand()) }')

#Get a link with all the relevant information
link=$(curl -X POST -H "Content-Type: application/json" -d '{"branch_key":"key_live_nlAouURn9O4oeYgJjPOVimddxvpOIUc0", "campaign":"'"$urlschemeString"'", "channel":"'"$applinksString"'", "tags":["twig"],"data":"{\"ios_bundle_id\":\"'"$bundleid"'\",\"ios_team_id\":\"'"$teamid"'\",\"branch_app_domain\":\"'"$branch_app_domain"'\",\"branch_key\":\"'"$branch_key"'\",\"entitlements\":\"'"$entitlementsIncluded"'\"}"}' https://api.branch.io/v1/url)
#Uncomment this line to see the raw configuration information
#echo -e "\n Branch App Domain : $branch_app_domain \n Branch Key : $branch_key \n Bundle ID : $bundleid \n Apple App Prefix : $teamid \n Entitlements Included : $entitlementsIncluded \n Entitlements Values : $applinksString \n URI Schemes : $urlschemeString "
#Give the user a cooki- I mean a link
echo -e "\n ####################################################### \n #   Click the link grown to test your configuration   # \n ####################################################### \n $link"
