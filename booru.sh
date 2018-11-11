#!/bin/bash
# Goal is to create a booru-esque browsing experience for storing images

# List of functions
# -Abillity to preform AND/OR seearches upon database
# -Abillity to add files
# -Abillity to delete files
# -Abillity to open files

version="17.9.13-git by Christian Silvermoon"

# Lock File Handling ---------#

function cleanup {
	#Cleans up junk
	ec=$?
	if [ "$lockexit" != "true" ]; then
		rm ".bbooru.lock"
	fi

	exit "$ec"

}

trap "cleanup" EXIT INT
if [ -e ".bbooru.lock" ]; then
	echo -e "\e[31;1mUnable to lock directory... is there another instance running?\nIf you believe this is an error try again after: rm \".bbooru.lock\" \e[0m"
	lockexit=true
	exit 1
fi
touch ".bbooru.lock"

# Functions ------------------#

function derpiget_idfiletype {
	#Use: derpiget_idfiletype FILENAME
	#Used to replace functionality of the 'mimetype' command of 'libfile-mimeinfo-perl'
	#Should echo back file extention
	mimetype=$(file -ib "$1" | cut -d';' -f 1)

	extention=$(< bbooru-mimetypes.csv grep -wE "^\"$mimetype\"" | tr -d '"' | cut -d',' -f 2)

	while [ "$extention" = "" ]; do
		echo -e "No extention found for Mimetype \"$mimetype\"" >&2 #Directed to STDERR to prevent setting extention to prompt output
		read -p "File Extention (Example: png): " extention
		echo -e "\n" >&2
		read -p "Type \"yes\" to confirm: " option
		if [ "$option" != "yes" ]; then
			unset extention
		else
			echo -e "Extention Registered to Mimetype.\n" >&2
			echo "\"$mimetype\",\"$extention\"" >> "bbooru-mimetypes.csv"
		fi
	done

	echo "$extention"

}


function database_mod {
	#Function for handlng carious modifications to database
	if [ "$1" = "--add" ]; then
		if [ ! -e "$2" ]; then
			echo -e "\e[31;1mInvalid File or Directory. Are you sure it exists?\e[0m"
			exit 1
		fi

		ID=$((db_highest_id + 1))
		FILETYPE=$(derpiget_idfiletype "$2")
		DATE=$(date)
		MD5SUM=($(md5sum "$2"))

		#Duplicate prevention
		if [ "$(database_query --md5Test "$MD5SUM")" != "" ]; then
			echo "File is already in database"
			database_query --md5match "$MD5SUM"
			if [ "$rmfileonfail" = "true" ]; then
				rm "$finalfilename"
			fi
			exit 1
		fi

		SIZE=($(du -sh "$2"))
		ORIGINAL_NAME=$(basename "$2")

		#Promptable input
		if [ "$3" = "" ]; then
			echo -en "\e[1mSource URLS:\e[0m "
			read SOURCES
		else
			SOURCES="$3"
		fi

		if [ "$4" = "" ]; then
			echo -en "\e[1mTags:\e[0m "
			read TAGS
		else
			TAGS="$4"
		fi

		#Sanatize tag input and account for aliases
		TAGS=$(echo "$TAGS" | tr -d ',' | tr -d '+' | tr -d '-' | tr -d '"' | tr -d '|' | sed 's/ $//g' | sed 's/^ //g')
		for tag in $TAGS; do
			tmptag=$(resolve_alias "$tag")
			if [ "$tag" != "$tmptag" ]; then
				echo -e "$tag \e[1m->\e[0m $tmptag"
				res_alias+="$tmptag "
			else
				res_alias+="$tag "
			fi
		done
		TAGS=$(echo "$res_alias" | sed 's/ $//g' | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//g')

		if [ "$5" = "" ]; then
			echo -en "\e[1mPersonal Comment:\e[0m "
			read COMMENT
		else
			COMMENT="$5"
		fi

		COMMENT=$(echo "$COMMENT" | sed 's/,/[c]/g' | sed 's/\"/[q]/g' | tr -d '|')

		echo -e "\"$ID\",\"$FILETYPE\",\"$DATE\",\"$MD5SUM\",\"$SIZE\",\"$ORIGINAL_NAME\",\"$SOURCES\",\"$TAGS\",\"$COMMENT\"" >> bbooru-db.csv
		database_mod --reorder
		cp "$2" "files/$ID.$FILETYPE"
		echo "Added File ID $ID."
	elif [ "$1" = "--reorder" ]; then
		database=$(< bbooru-db.csv sort -V | grep -v "^$")
		echo "$database" > bbooru-db.csv
		#echo "Reordered Database"
	fi
}

function database_query {
	#Retrieve Information from Database
	if [ "$1" = "--highestID" ]; then
		database_mod --reorder
		tmp_highestID=$(< bbooru-db.csv tail -1 | cut -d',' -f 1 | tr -d '"' | tail -1)
		if [ "$tmp_highestID" = "" ]; then
			tmp_highestID=0
		fi

		echo "$tmp_highestID"
		unset tmp_highestID

	elif [ "$1" = "--filetype" ]; then
		< bbooru-db.csv grep "^\"$2\"" | cut -d',' -f 2 | tr -d '"'

	elif [ "$1" = "--originalName" ]; then
		< bbooru-db.csv grep "^\"$2\"" | cut -d',' -f 6 | tr -d '"'

	elif [ "$1" = "--comment" ]; then
		< bbooru-db.csv grep "^\"$2\"" | cut -d',' -f 9 | sed 's/^"//g' | sed 's/"$//g'

	elif [ "$1" = "--tags" ]; then
		< bbooru-db.csv grep "^\"$2\"" | cut -d',' -f 8 | tr -d '"'

	elif [ "$1" = "--source" ]; then
		< bbooru-db.csv grep "^\"$2\"" | cut -d',' -f 7 | tr -d '"'

	elif [ "$1" = "--idTest" ]; then
		< bbooru-db.csv cut -d',' -f 1 | tr -d '"' | grep "^$2$"

	elif [ "$1" = "--md5Test" ]; then
		< bbooru-db.csv cut -d',' -f 4 | tr -d '"' | grep "$2"

	elif [ "$1" = "--md5match" ]; then
		< bbooru-db.csv awk -F "\",\"" '{print "MD5 Matches ID "$1" \033[2m("$4")\033[0m\n"}' | tr -d '"' | grep "$2"
	fi
}

function help_message {
	#Outputs help message
	echo -e "\e[1mUSAGE\n\e[0m  bbooru <ARGS>\n"

	echo -e "\e[1mARGUMENTS\e[0m"
	echo -e "  --add <FILE> [src] [tags] [com]  Add file to BASH-Booru"
	echo -e "  --add-csv <FILE>                 Add using a Shimmie2 Bulk_Add_CSV file"
	echo -e "  --add-derpi <URL>                Add from Derpibooru URL"
	echo -e "  --add-wget <URL>                 Download URL and add to BASH-Booru"
	echo -e "  --edit-com <ID>                  Edit file's Comment"
	echo -e "  --edit-src <ID>                  Edit file's Sources"
	echo -e "  --edit-tags <ID>                 Edit file's Tags\e[0m"
	echo -e "  --extract <IDs>                  Extract files with their origianl name"
	echo -e "  --list                           List files in database"
	echo -e "  --list-tags                      Displays list of all tags with use count"
	echo -e "  --help                           Display this message"
	echo -e "  --info                           Output info about the database and files"
	echo -e "  --random                         Show a random file"
	echo -e "  --random-open                    Open a radnom file"
	echo -e "\e[2m  --remove <ID>                    Delete file from BASH-booru\e[0m"
	echo -e "  --open <ID>                      Open file using handler"
	echo -e "\e[2m  --pool-edit-desc <ID>            Edit Pool Description\e[0m"
	echo -e "\e[2m  --pool-edit-ids <ID>             Add/Remove files from pool\e[0m"
	echo -e "\e[2m  --pool-edit-name <ID>            Rename Pool\e[0m"
	echo -e "\e[2m  --pool-mk <Name> [IDs] [Desc]    Create a new pool\e[0m"
	echo -e "\e[2m  --pool-rm <ID>                   Delete Pool\e[0m"
	echo -e "  --search <Query>                 Search database for files"
	echo -e "  --sym-search <Query>			Search and store results as symlinks"
	echo -e "  --show <ID>                      Show all details on a file"
	echo -e "  --tag-info <Tag>                 Show details about a tag"
	echo -e "  --version                        Outputs version number"

}

function resolve_alias {
	alias_check=$(< bbooru-tag_aliases.csv grep -v "^#" | grep "^\"$1\"" | head -1)
	if [ "$alias_check" = "" ]; then
		echo "$1"
	else
		echo "$alias_check" | cut -d',' -f 2 | tr -d '"'
	fi
}

function derpiget {
	#port of DerpiGET's Page disection/download function

	#Verify that "$1" is a valid Derpibooru post URL
	if [ "$(echo "$1" | cut -d'?' -f 1 | grep -E "^http(s|)://derpibooru.org/[0-9]*$")" = "" ]; then
		echo "Invalid Derpibooru Post URL!"
		exit 1
	fi

	html="$(wget -q -O- "$1" | sed 's/>/>\n/g')"

	wget -q -O ".bbooru-derpiget.tmp" "$(echo "$html" | grep "View (no tags in filename)" | sed 's/\" /\"\n/g' | sed 's/href=\"/http:/g' | sed 's/\">//g' | grep "http:" | sed 's/http:/https:/g' | tr -d '"' | sed 's/<a //g')"

	json=$(wget -q -O- "$(echo "$1" | cut -d'?' -f 1).json")
	tags=$(echo "$html" | grep "tag dropdown" | sed 's/\" /\"\n/g' | grep "data-tag-name=" | cut -d"=" -f 2 | sed 's/\"//g' | tr '\n' ',' | sed 's/,/, /g')
	tags=$(echo "$tags" | sed "s/&#39;/'/g" | sed 's/, /,/g' | tr ' ' '_' | tr ',' ' ')
	#echo -e "\e[1mTAGS\n\e[0m$tags\n\n"

	description="$(echo "$json" | sed 's/\\u003e\\u003e/https:\/\/derpibooru.org\//g' | sed 's/","/",\n"/g' | grep "^\"description" | cut -d':' -f 2- | sed 's/^"//g' | sed 's/",$//g' | sed 's/\\r\\n/|/g' | sed 's/\\"/[q]/g' | sed 's/,/[c]/g' | sed 's/\[spoiler\]//g' | sed 's/\[\/spoiler\]//g' | sed 's/\[bq\]/[n]----------[n]/g' | sed 's/\[\/bq\]/[n]----------[n]/g')"

	# sed -r -e 's/^.{60}/&[n]/'
	if [ "$description" = "" ]; then
		description="No Description. $(echo "$tags" | cut -d' ' -f 1-4)"
		description="$(echo "$description" | cut -c 1-60)"
	else
		if [ "$(echo "$description" | cut -d'|' -f 1 | wc -c)" -gt "60" ]; then
			description="$(echo "$description" | sed -r -e 's/^.{60}/&|/')"
		fi
	fi
	description="$(echo "$description" | sed 's/|/[n]/g')"

	#echo -e "\e[1mDESCRIPTION\e[0m\n$description\n\n"

	source=$(echo "$html" | grep "dc:source" | sed 's/\" /\"\n/g' | grep "href=" | sed 's/href=\"//g' | sed 's/\">//g')
	#echo -e "\e[1mSOURCE\e[0m\n$source $(echo "$1" | cut -d'?' -f 1)"

	TAGS="$tags"
	SOURCE="$source $(echo "$1" | cut -d'?' -f 1)"
	COMMENT="$description"

}

# /Functions -----------------#

echo ""

#IF database doesn't exist, create one
if [ ! -e "bbooru-db.csv" ]; then
	echo "Missing Database, creating..."
	touch "bbooru-db.csv"
fi

#IF aliases file not found
if [ ! -e "bbooru-tag_aliases.csv" ]; then
	echo "Missing alias list, creating..."
	touch "bbooru-tag_aliases.csv"
fi

#IF File handler configuration is missing
if [ ! -e "bbooru-file_handlers.conf" ]; then
	echo "File handler configuration missing, creating"
	echo "N FALLBACK xdg-open %FILE%" > "bbooru-file_handlers.conf"
fi

#If the mimetype data is missing
if [ ! -e "bbooru-mimetypes.csv" ]; then
	echo "Mimetype data missing, creating..."
	echo -e "\"image/png\",\"png\"\n\"image/jpeg\",\"jpeg\"\n\"application/vnd.oasis.opendocument.text\",\"odt\"\n\"video/webm\",\"webm\"\n\"image/gif\",\"gif\"\n\"text/plain\",\"txt\"\n\"application/x-shockwave-flash\",\"swf\"\n\"application/x-dosexec\",\"exe\"\n\"application/epub+zip\",\"epub\"\n\"application/pdf\",\"pdf\"\n\"video/mp4\",\"mp4\"\n\"text/x-shellscript\",\"sh\"\n\"application/java-archive\",\"jar\"\n\"audio/mpeg\",\"mp3\"\n\"audio/ogg\",\"ogg\"\n\"application/x-iso9660-image\",\"iso\"" > bbooru-mimetypes.csv
fi

#Create Pool Files
if [ ! -e "bbooru-pools.csv" ]; then
	echo "Pools data missing, creating.."
	touch "bbooru-pools.csv"
fi

#IF Files Directory is missing
if [ ! -d "files" ]; then
	echo "Creating missing directory: \"files\""
	mkdir "files"
fi

db_entry_count=$(< bbooru-db.csv wc -l)
db_highest_id=$(database_query --highestID)

if [ "$1" = "--list" ]; then
	#List all posts
	database_mod --reorder
	if [ "$(cat bbooru-db.csv)" = "" ]; then
		echo -e "\e[1mDatabase is empty, nothing to list.\e[0m"
		exit
	fi
	< bbooru-db.csv awk -F "\",\"" '{print "\033[1m"$1": ["$2"/"$5"] "$9"\033[0m\n" $8"\n"}' | sed 's/\[n\].*$/ [+]/g' | sed -r "s/(\[\+]+.*$)/$(printf "\033[32;1m")\1$(printf "\033[0m")/g"  |  tr -d '"' | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g'

elif [ "$1" = "--tag-info" ]; then
	if [ "$2" != "" ]; then
		tag=$(resolve_alias "$2")
		echo -en "\e[1mTag: \e[0m$tag "
		if [ "$tag" != "$2" ]; then
			echo -e "\e[2m(From Alias \"$2\")\e[0m"
		else
			echo ""
		fi
		echo -en "\e[1mPosts with this tag: \e[0m"
		< bbooru-db.csv cut -d',' -f 8 | grep -cwE "$tag"
		echo -e "\e[1mAliases: \e[0m"
		< bbooru-tag_aliases.csv grep "\"$tag\"$" | tr -d '"' | awk -F "," '{print $1"\033[1m -> \033[0m" $2}'

	else
		echo -e "\e[31;1mNo tag specified.\e[0m"
		exit 1
	fi

elif [ "$1" = "--add-csv" ]; then
	#add files using a Shimmie2 bulk_add_csv file
	if [ -e "$2" ]; then #Check for existance of CSV

		entry_count=$(< "$2" wc -l) #Get the total number of entries
		counter="1" #Set counter variable
		mdf_skip="0" #Files skipped due to duplicacte MD5s
		while [ "$counter" != "$((entry_count + 1))" ]; do
			#Interate through list, checking to ensure all files listed exist
			focus_line=$(< "$2" head -$counter | tail -1)

			if [ ! -e "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')" ]; then
				echo -e "\e[31;1mEntry \"$counter\" in \"$2\" does not point to an existing file.\e[0m"
				exit 1
			else
				MD5=($(md5sum "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')"))
				#Duplicate prevention
				if [ "$(database_query --md5Test "$MD5")" = "" ]; then
					dedupe_csv+="$focus_line|"
				else
					mdf_skip=$((mdf_skip + 1))
				fi

			fi

			counter=$((counter + 1))
		done

		if [ "$mdf_skip" -ge "$entry_count" ]; then
			echo -e "\e[31;1mAll Entries matched MD5s in the Database. Nothing to do.\e[0m"
			exit 1
		fi

		dedupe_csv=$(echo "$dedupe_csv" | tr '|' '\n')
		entry_count=$(echo "$dedupe_csv" | wc -l)

		if [ "$mdf_skip" != "0" ]; then
			echo -e "\e[31;1mIgnoring $mdf_skip/$entry_count entries because they match MD5s in the Database...\e[0m"
		fi

		counter="1" #Reset counter variable again

		while [ "$counter" != "$((entry_count + 1))" ]; do
			#Iterate through list, extracting and preparing information for adding files
			focus_line=$( echo "$dedupe_csv" | head -$counter | tail -1)
			unset TAGS
			unset res_alias

			#ID
			ID=$((db_highest_id + counter))
			#FILETYPE
			FILETYPE=$(derpiget_idfiletype "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')")
			#MD5
			MD5=($(md5sum "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')"))

			#SIZE
			SIZE=($(du -sh "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')"))
			#FILENAME
			ORIGINAL_NAME=$(basename "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')")

			#SOURCE
			SOURCE=$(echo "$focus_line" | cut -d',' -f 3 | tr -d '"')
			#TAGS
			TAGS=$(echo "$focus_line" | cut -d',' -f 2 | tr -d '"')
			#Sanatize tag input and account for aliases

			TAGS=$(echo "$TAGS" | tr -d ',' | tr -d '+' | tr -d '-' | tr -d '"' | tr -d '|' | sed 's/ $//g' | sed 's/^ //g')
			for tag in $TAGS; do
				tmptag=$(resolve_alias "$tag")
				if [ "$tag" != "$tmptag" ]; then
					#echo -e "$tag \e[1m->\e[0m $tmptag"
					res_alias+="$tmptag "
				else
					res_alias+="$tag "
				fi
			done
			TAGS=$(echo "$res_alias" | sed 's/ $//g' | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//g')

			#COMMENT (Will Generate From Source)
			COMMENT="$(echo "$SOURCE" | cut -d' ' -f 1)"

			cp "$(echo "$focus_line" | cut -d',' -f 1 | tr -d '"')" "files/$ID.$FILETYPE"
			echo "\"$ID\",\"$FILETYPE\",\"$(date)\",\"$MD5\",\"$SIZE\",\"$ORIGINAL_NAME\",\"$SOURCE\",\"$TAGS\",\"$COMMENT\"" >> bbooru-db.csv

			counter=$((counter + 1))
		done

	else
		echo -e "\e[31;1mFile not found... are you sure it exists?\e[0m"
		exit 1
	fi

elif [ "$1" = "--add-derpi" ]; then
	SOURCE="3"
	TAGS="2"
	COMMENT="1"
	derpiget "$2"
	rmfileonfail="true"

	wfile=$RANDOM
	finalfilename="$wfile.$(derpiget_idfiletype ".bbooru-derpiget.tmp")"

	until [ ! -e "$finalfilename" ]; do
		wfile=$RANDOM
		finalfilename="$wfile.$(derpiget_idfiletype ".bbooru-derpiget.tmp")"
	done

	mv ".bbooru-derpiget.tmp" "$finalfilename"
	database_mod --add "$finalfilename" "$SOURCE" "$TAGS" "$COMMENT"
	rm "$finalfilename"

elif [ "$1" = "--list-tags" ]; then
	#List all tags
	alltags=$(< bbooru-db.csv cut -d',' -f 8 | tr -d '"' | tr ' ' '\n' | sort)
	uniqtags=$(< bbooru-db.csv cut -d',' -f 8 | tr -d '"' | tr ' ' '\n' | sort -u | tr '\n' ' ')
	#echo -e "\e[1mUnique Tags: \e[0m$(echo $uniqtags | tr ' ' '\n' | wc -l)\n"
	for tag in $uniqtags; do
		echo "$tag ($(echo "$alltags" | grep -cwE "$tag"))"
	done
elif [ "$1" = "--search" ]; then
	if [ "$2" != "" ]; then
		search_results=$(< bbooru-db.csv awk -F "\",\"" '{print "POSTID_"$1" FILETYPE_"$2" MD5_"$4" "$8}' | tr -d '"')
		for tag in $2; do
			#Search resolution functions
			if [[ "$tag" == *"|"* ]]; then
				#Tag contains OR operator
				#First resolve aliases
				tag=$(echo "$tag" | tr '|' ' ')
				for tmptag in $tag; do
					res_alias+="$(resolve_alias "$tmptag") "
				done

				res_alias=$(echo "$res_alias" | sed 's/ $//g')
				tag=$(echo "$res_alias" | tr ' ' '|')
				unset res_alias
				search_query+="$tag "

				search_results=$(echo "$search_results" | grep -wE "$(echo "$tag" |  sed -r 's/\(/\\\(/g' | sed -r 's/\)/\\\)/g')" )

			elif [ "$(echo "$tag" | cut -c 1)" = "-" ]; then
				tag=$(echo "$tag" | cut -c 2-)
				tag=$(resolve_alias "$tag")
				search_query+="-$tag "

				search_results=$(echo "$search_results" | grep -wvE "$(echo "$tag" |  sed -r 's/\(/\\\(/g' | sed -r 's/\)/\\\)/g')")
			else
				tag=$(resolve_alias "$tag")
				search_results=$(echo "$search_results" | grep -wE "$(echo "$tag" |  sed -r 's/\(/\\\(/g' | sed -r 's/\)/\\\)/g')")
				search_query+="$tag "
			fi
		done
		search_query=$(echo "$search_query" | sed 's/ $//g')
		result_count=$(echo "$search_results" | tr ' ' '\n' | grep -c "POSTID")
		search_results=$(echo "$search_results" | tr ' ' '\n' | grep "POSTID" | sed 's/POSTID_//g' | tr '\n' ' ')

		echo -e "\e[1mSearch Results for: \e[7m$search_query\e[0m\n"
		#POST display information
		if [ "$search_results" != "" ]; then
			echo -e "\e[1mFound \e[1;32m$result_count\e[0;1m Result$(if [ "$result_count" != "1" ]; then echo "s"; fi)\e[0m\n"
			for postid in $search_results; do
				< bbooru-db.csv grep "^\"$postid\"" | awk -F "\",\"" '{print "\033[1m"$1": ["$2"/"$5"] "$9"\033[0m\n" $8"\n"}' | sed 's/\[n\].*$/ [+]/g' | sed -r "s/(\[\+]+.*$)/$(printf "\033[32;1m")\1$(printf "\033[0m")/g"  |  tr -d '"' | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g'
			done
		else
			echo -e "\e[31;1mNo Results\e[0m"
			exit
		fi
	else
		echo -e "\e[31;1mYou must specifiy a search query!\e[0m"
		exit 1
	fi

elif [ "$1" = "--sym-search" ]; then
	if [ "$2" != "" ]; then
		search_results=$(< bbooru-db.csv awk -F "\",\"" '{print "POSTID_"$1" FILETYPE_"$2" MD5_"$4" "$8}' | tr -d '"')
		for tag in $2; do
			#Search resolution functions
			if [[ "$tag" == *"|"* ]]; then
				#Tag contains OR operator
				#First resolve aliases
				tag=$(echo "$tag" | tr '|' ' ')
				for tmptag in $tag; do
					res_alias+="$(resolve_alias "$tmptag") "
				done

				res_alias=$(echo "$res_alias" | sed 's/ $//g')
				tag=$(echo "$res_alias" | tr ' ' '|')
				unset res_alias
				search_query+="$tag "

				search_results=$(echo "$search_results" | grep -wE "$(echo "$tag" |  sed -r 's/\(/\\\(/g' | sed -r 's/\)/\\\)/g')" )

			elif [ "$(echo "$tag" | cut -c 1)" = "-" ]; then
				tag=$(echo "$tag" | cut -c 2-)
				tag=$(resolve_alias "$tag")
				search_query+="-$tag "

				search_results=$(echo "$search_results" | grep -wvE "$(echo "$tag" |  sed -r 's/\(/\\\(/g' | sed -r 's/\)/\\\)/g')")
			else
				tag=$(resolve_alias "$tag")
				search_results=$(echo "$search_results" | grep -wE "$(echo "$tag" |  sed -r 's/\(/\\\(/g' | sed -r 's/\)/\\\)/g')")
				search_query+="$tag "
			fi
		done
		search_query=$(echo "$search_query" | sed 's/ $//g')
		result_count=$(echo "$search_results" | tr ' ' '\n' | grep -c "POSTID")
		search_results=$(echo "$search_results" | tr ' ' '\n' | grep "POSTID" | sed 's/POSTID_//g' | tr '\n' ' ')
		echo "$search_results";

		echo -e "\e[1mSearch Results for: \e[7m$search_query\e[0m\n"
		#POST display information
		if [ "$search_results" != "" ]; then
			echo -e "\e[1mFound \e[1;32m$result_count\e[0;1m Result$(if [ "$result_count" != "1" ]; then echo "s"; fi)\e[0m\n"
			for postid in $search_results; do
				< bbooru-db.csv grep "^\"$postid\"" | awk -F "\",\"" '{print "\033[1m"$1": ["$2"/"$5"] "$9"\033[0m\n" $8"\n"}' | sed 's/\[n\].*$/ [+]/g' | sed -r "s/(\[\+]+.*$)/$(printf "\033[32;1m")\1$(printf "\033[0m")/g"  |  tr -d '"' | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g'
				if [ ! -d "search_results" ]; then
					mkdir "search_results"
				fi
				rm -rf "search_results/*" #Clear old
				filename=$(< bbooru-db.csv grep "^\"$postid\"" | sed 's/^\"//g' | awk -F "\",\"" '{print $1"."$2}')

				ln -sf "$PWD/files/$filename" "search_results/$filename"
			done
				echo -e "\e[1mSearch results symlinked to \"search_results\"\e[0m"
		else
			echo -e "\e[31;1mNo Results\e[0m"
			exit
		fi
	else
		echo -e "\e[31;1mYou must specifiy a search query!\e[0m"
		exit 1
	fi


elif [ "$1" = "--random" ]; then
	< bbooru-db.csv grep "^\"$(< bbooru-db.csv cut -d',' -f 1 | tr -d '"' | sort -R | head -1)\"" | sed 's/^"//g' | sed 's/"$//g' | awk -F "\",\"" '{print "\033[1mID: \033[0m"$1"\n\033[1mFile Type: \033[0m"$2"\n\033[1mDate Added: \033[0m"$3"\n\033[1mMD5: \033[0m"$4"\n\033[1mSize: \033[0m"$5"\n\033[1mOriginal Name: \033[0m"$6"\n\033[1mSource: \033[0m"$7"\n\033[1mTags: \033[0m"$8"\n\033[1mComment: \033[0m"$9}' | sed 's/\[n\]/\n/g' | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g'

elif [ "$1" = "--show" ]; then
	#Show more detailed info about a post
	if [ "$2" != "" ]; then
		if [ "$(database_query --idTest "$2")" != "" ]; then
			< bbooru-db.csv grep "^\"$2\"" | sed 's/^"//g' | sed 's/"$//g' | awk -F "\",\"" '{print "\033[1mID: \033[0m"$1"\n\033[1mFile Type: \033[0m"$2"\n\033[1mDate Added: \033[0m"$3"\n\033[1mMD5: \033[0m"$4"\n\033[1mSize: \033[0m"$5"\n\033[1mOriginal Name: \033[0m"$6"\n\033[1mSource: \033[0m"$7"\n\033[1mTags: \033[0m"$8"\n\033[1mComment: \033[0m"$9}' | sed 's/\[n\]/\n/g' | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g'
		else
			echo -e "\e[31;1mFile ID \"$2\" does not exist in Database.\e[0m"
			exit 1
		fi
	else
		echo -e "\e[31;1mNo File ID specified for showing.\e[0m"
		exit 1
	fi

elif [ "$1" = "--edit-tags" ]; then
	if [ "$2" != "" ]; then
		if [ "$(database_query --idTest "$2")" != "" ]; then
			#OH BOY
			entry_all=$(< bbooru-db.csv grep "^\"$2\"")
			entry_p1=$(echo "$entry_all" | cut -d',' -f 1-7)
			entry_p2=$(echo "$entry_all" | cut -d',' -f 9-)

			echo -e "\e[0;1mPOST $2's Old Tags:\e[0m"
			database_query --tags "$2"

			echo -e "\n\e[2mHint: You can use backspace, etc. to edit the tags below. Finish with the enter key!\n\nHint: Seperate tags with spaces, if they have spaces in their names use an \"_\" instead!\e[0m"
			echo -e "\n\e[1mPOST $2's New Tags:\e[0m"

			read -ei "$(database_query --tags "$2")" TAGS
			echo ""

			TAGS=$(echo "$TAGS" | tr -d ',' | tr -d '+' | tr -d '-' | tr -d '"' | tr -d '|' | sed 's/ $//g' | sed 's/^ //g')
			for tag in $TAGS; do
				tmptag=$(resolve_alias "$tag")
				if [ "$tag" != "$tmptag" ]; then
					echo -e "$tag \e[1m->\e[0m $tmptag"
					res_alias+="$tmptag "
				else
					res_alias+="$tag "
				fi
			done
			TAGS=$(echo "$res_alias" | sed 's/ $//g' | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//g')

			read -p "Type \"yes\" to confirm changes: " option
			if [ "$option" = "yes" ]; then
				tmpdb=$(< bbooru-db.csv grep -v "^\"$2\"")
				echo "$tmpdb" > bbooru-db.csv
				echo "$entry_p1,\"$TAGS\",$entry_p2" >> bbooru-db.csv
				database_mod --reorder
			else
				echo "Recieved \"$option\" instead of \"yes\", aborted."
				exit
			fi

		else
			echo -e "\e[31;1mFile ID \"$2\" does not exist in Database.\e[0m"
			exit 1
		fi
	else
		echo -e "\e[31;1mNo File ID specified for editing.\e[0m"
		exit 1
		echo "$entry_p1,\"$SOURCE\",$entry_p2" >> bbooru-db.csv
	fi

elif [ "$1" = "--edit-src" ]; then
	if [ "$2" != "" ]; then
		if [ "$(database_query --idTest "$2")" != "" ]; then
			#OH BOY
			entry_all=$(< bbooru-db.csv grep "^\"$2\"")
			entry_p1=$(echo "$entry_all" | cut -d',' -f 1-6)
			entry_p2=$(echo "$entry_all" | cut -d',' -f 8-)

			echo -e "\e[0;1mPOST $2's Old Source:\e[0m"
			database_query --source "$2"

			echo -e "\n\e[2mHint: You can use backspace, etc. to edit the source below. Finish with the enter key!\n\nHint: You can specify as many sources as you like\e[0m"
			echo -e "\n\e[1mPOST $2's New Source:\e[0m"

			read -ei "$(database_query --source "$2")" SOURCE
			echo ""

			SOURCE=$(echo "$SOURCE" | tr -d ',' | tr -d '"' | tr -d '|') #Sanatize Input
			read -p "Type \"yes\" to confirm changes: " option
			if [ "$option" = "yes" ]; then
				tmpdb=$(< bbooru-db.csv grep -v "^\"$2\"")
				echo "$tmpdb" > bbooru-db.csv
				database_mod --reorder
			else
				echo "Recieved \"$option\" instead of \"yes\", aborted."
				exit
			fi

		else
			echo -e "\e[31;1mFile ID \"$2\" does not exist in Database.\e[0m"
			exit 1
		fi
	else
		echo -e "\e[31;1mNo File ID specified for editing.\e[0m"
		exit 1
	fi

elif [ "$1" = "--edit-com" ]; then
	if [ "$2" != "" ]; then
		if [ "$(database_query --idTest "$2")" != "" ]; then
			#OH BOY
			entry_all=$(< bbooru-db.csv grep "^\"$2\"")
			entry_p1=$(echo "$entry_all" | cut -d',' -f 1-8)

			echo -e "\e[0;1mPOST $2's Old Comment:\e[0m"
			database_query --comment "$2" | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g'

			echo -e "\n\e[2mHint: You can use backspace, etc. to edit the comment below. Finish with the enter key!\n\n[n] is interpereted as new line on output.\e[0m"
			echo -e "\n\e[1mPOST $2's New Comment:\e[0m"

			read -ei "$(database_query --comment "$2" | sed 's/\[c\]/,/g' | sed 's/\[q\]/\"/g')" COMMENT
			echo ""

			read -p "Type \"yes\" to confirm changes: " option
			if [ "$option" = "yes" ]; then

				tmpdb=$(< bbooru-db.csv grep -v "^\"$2\"")
				echo "$tmpdb" > bbooru-db.csv
				COMMENT=$(echo "$COMMENT" | tr -d '|' | sed 's/,/[c]/g' | sed 's/\"/[q]/g') #Sanatize Input
				echo "$entry_p1,\"$COMMENT\"" >> bbooru-db.csv
				database_mod --reorder
			else
				echo "Recieved \"$option\" instead of \"yes\", aborted."
				exit
			fi

		else
			echo -e "\e[31;1mFile ID \"$2\" does not exist in Database.\e[0m"
			exit 1
		fi
	else
		echo -e "\e[31;1mNo File ID specified for editing.\e[0m"
		exit 1
	fi


elif [ "$1" = "--add" ]; then
	database_mod --add "$2" "$3" "$4" "$5"

elif [ "$1" = "--add-wget" ]; then
	rmfileonfail="true"
	wget -q -O ".bbooru-wget.tmp" "$2"

	wfile=$RANDOM
	finalfilename="$wfile.$(derpiget_idfiletype ".bbooru-wget.tmp")"

	until [ ! -e "$finalfilename" ]; do
		wfile=$RANDOM
		finalfilename="$wfile.$(derpiget_idfiletype ".bbooru-wget.tmp")"
	done

	mv ".bbooru-wget.tmp" "$finalfilename"
	database_mod --add "$finalfilename" "$3" "$4" "$5"
	rm "$finalfilename"

elif [ "$1" = "--extract" ]; then
	if [ "$2" != "" ]; then
		for EXTRACT_ID in "$@"; do
			if [ "$EXTRACT_ID" != "--extract" ]; then
				if [ "$(database_query --idTest "$EXTRACT_ID")" != "" ]; then
					echo "$EXTRACT_ID: $(database_query --originalName "$EXTRACT_ID")"
					cp "files/$EXTRACT_ID.$(database_query --filetype "$EXTRACT_ID")" "$(database_query --originalName "$EXTRACT_ID")"
				else
					echo -e "\e[31;1mFile ID \"$EXTRACT_ID\" does not exist in Database.\e[0m"
				fi
			fi
		done
	else
		echo -e "\e[31;1mNo File ID specified for extraction.\e[0m"
		exit 1
	fi

elif [ "$1" = "--remove" ]; then
	if [ "$2" != "" ]; then
		if [ "$(database_query --idTest "$2")" != "" ]; then
			< bbooru-db.csv grep "^\"$2\"" | sed 's/^"//g' | sed 's/"$//g' | awk -F "\",\"" '{print "\033[1mID: \033[0m"$1"\n\033[1mFile Type: \033[0m"$2"\n\033[1mDate Added: \033[0m"$3"\n\033[1mMD5: \033[0m"$4"\n\033[1mSize: \033[0m"$5"\n\033[1mOriginal Name: \033[0m"$6"\n\033[1mSource: \033[0m"$7"\n\033[1mTags: \033[0m"$8"\n\033[1mComment: \033[0m"$9}' | sed 's/\[n\]/\n/g'
			echo -e "\n\e[31;1mAre you sure you want to delete this file?\e[0m\n"
			read -p "Please type \"Yes\" to confirm: " option

			if [ "$option" = "yes" ]; then
				rm "files/$2.$(database_query --filetype "$2")"
				tmpdb=$(< bbooru-db.csv grep -v "^\"$2\"")
				echo "$tmpdb" > bbooru-db.csv
				echo "Post $2 was removed."
				database_mod --reorder
			else
				echo "Recieved \"$option\" instead of \"yes\", aborted."
				exit
			fi

		else
			echo -e "\e[31;1mFile ID \"$2\" does not exist in Database.\e[0m"
		fi
	else
		echo -e "\e[31;1mNo File ID specified for removal.\e[0m"
		exit 1
	fi

elif [ "$1" = "--info" ]; then
	echo "Database Entries: $db_entry_count"
	echo "Highest ID in Database: $db_highest_id"
	db_size=($(du -sh bbooru-db.csv))
	echo -e "\nSize of Database: $db_size"
	files_size=($(du -sh files))
	echo "Size of Files: $files_size"

elif [ "$1" = "--random-open" ]; then
	id="$(< bbooru-db.csv cut -d',' -f 1 | tr -d '"' | sort -R | head -1)"
	if [ -e "files/$id.$(database_query --filetype "$id")" ]; then
		#Determine Handler for file type
		handler=$(< bbooru-file_handlers.conf grep "^[QSNH] $(database_query --filetype "$id")" | cut -d' ' -f 1,3-)
		if [ "$handler" = "" ]; then
			handler=$(< bbooru-file_handlers.conf grep "^[QSNH] FALLBACK" | cut -d' ' -f 1,3-)
		fi

		#Determine Output Style
		handlerCMD="$(echo "$handler" | cut -d' ' -f 2- | sed "s/%FILE%/files\/$id.$(database_query --filetype "$id")/g")"
		if [ "$(echo "$handler" | cut -d' ' -f 1)" = "S" ]; then
			#Standard Output
			#echo "STANDARD"
			$handlerCMD &
		elif [ "$(echo "$handlerCMD" | cut -d' ' -f 1)" = "Q" ]; then
			#Quiet Output (STDERR only)
			#echo "QUIET"
			$handlerCMD > /dev/null &
		elif [ "$(echo "$handler" | cut -d' ' -f 1)" = "N" ]; then
			#NULL Output (No output at all)
			#echo "NULL"
			$handlerCMD > /dev/null 2>&1 &
		elif [ "$(echo "$handler" | cut -d' ' -f 1)" = "H" ]; then
			#HALT Mode, freeze script until program exits
			#Useful for interactive CLI applications
			#echo "HALT"
			$handlerCMD
		else
			echo -e "\e[31;1mbbooru-file_hanlders.conf error: Invalid Output Mode. Using Standard.\e[0m"
			$handlerCMD &
		fi
	else
		echo -e "\e[31;1mFile is missing from disk!\e[0m"
		exit 1
	fi

elif [ "$1" = "--open" ]; then
	if [ "$2" != "" ]; then
		if [ "$(database_query --idTest "$2")" != "" ]; then
			if [ -e "files/$2.$(database_query --filetype "$2")" ]; then
				#Determine Handler for file type
				handler=$(< bbooru-file_handlers.conf grep "^[QSNH] $(database_query --filetype "$2")" | cut -d' ' -f 1,3-)
				if [ "$handler" = "" ]; then
					handler=$(< bbooru-file_handlers.conf grep "^[QSNH] FALLBACK" | cut -d' ' -f 1,3-)
				fi

				#Determine Output Style
				handlerCMD="$(echo "$handler" | cut -d' ' -f 2- | sed "s/%FILE%/files\/$2.$(database_query --filetype "$2")/g")"
				if [ "$(echo "$handler" | cut -d' ' -f 1)" = "S" ]; then
					#Standard Output
					#echo "STANDARD"
					$handlerCMD &
				elif [ "$(echo "$handlerCMD" | cut -d' ' -f 1)" = "Q" ]; then
					#Quiet Output (STDERR only)
					#echo "QUIET"
					$handlerCMD > /dev/null &
				elif [ "$(echo "$handler" | cut -d' ' -f 1)" = "N" ]; then
					#NULL Output (No output at all)
					#echo "NULL"
					$handlerCMD > /dev/null 2>&1 &
				elif [ "$(echo "$handler" | cut -d' ' -f 1)" = "H" ]; then
					#HALT Mode, freeze script until program exits
					#Useful for interactive CLI applications
					#echo "HALT"
					$handlerCMD
				else
					echo -e "\e[31;1mbbooru-file_hanlders.conf error: Invalid Output Mode. Using Standard.\e[0m"
					$handlerCMD &
				fi
			else
				echo -e "\e[31;1mFile is missing from disk!\e[0m"
				exit 1
			fi
		else
			echo -e "\e[31;1mFile ID \"$2\" does not exist in Database.\e[0m"
			exit 1
		fi
	else
		echo -e "\e[31;1mNo File ID specified for opening.\e[0m"
		exit 1
	fi

elif [ "$1" = "--version" ]; then
	echo -e "BASH-Booru Version:\n$version"

elif [ "$1" = "--help" ]; then
	help_message
	exit

elif [ "$1" = "" ]; then
	echo "See \"--help\" for a list of arguments"
else
	echo -e "\e[31;1mInvalid Argument\e[0m"
	exit 1
fi
