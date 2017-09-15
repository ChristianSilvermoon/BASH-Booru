# BASH-Booru
A file management program designed to function similarly to a booru-style imageboard.

Files are added to a `csv` file that BASH-Booru uses as a database, and files are copied to the `files` folder, named after their post ID.

## Features
There are a few... this aims to replicate most of what you can do using an booru-style website, keep in mind.

#### Arguments

| Argument | What it does |
| --- | ---- |
| --add (FILE) | Add file to BASH-booru |
| --add-csv (FILE) | Add using a [Shimmie2](https://github.com/shish/shimmie2) Bulk_Add_CSV file |
| --add-derpi (URL) | Download and add a post from [Derpibooru](https://derpibooru.org) |
| --add-wget (URL) | Uses `wget` to download a file using a direct link |
| --edit-com (ID) | Edit file's Comment |
| --edit-src (ID) | Edit file's Sources |
| --edit-tags (ID) | Edit file's Tags |
| --extract (IDs) | Extract files with their original name |
| --list | List files in database |
| --list-tags | Displays list of all tags and their use count |
| --help | Display help message |
| --info | Output some info about the database and files |
| --random | Show a random file |
| --random-open | Open a random file |
| --remove (ID) | Delete file from BASH-booru |
| --open (ID) | Open file using handler |
| --search (Query) | Search database |
| --show (ID) | Show all details on a file |
| --tag-info (Tag) | Show details about a tag |

For more usage info, see the output of the `--help` argument!

Darkened arguments in `--help` are unavailable. This is due to unimplemented features at this time.

#### Search Syntax
How do you USE the search feature exactly?
There are two operators used, the `|` (OR) operator and the `-` (NOT) operator

A search could look like: `tag|tag2 -tag3 tag4`

which would mean the image has to contain: tag1 OR tag2, NOT tag3, tag4

You can use OR on as many tags as you want, but you ***cannot*** combined OR and NOT to form NOR... though this may be explored in the future.

This means that: `tag1|tag3|tag5|tag7` is a completely valid query!

Things that *aren't tags* can also be queried as if they were.
These things can be queried like so

`FILETYPE_png` will include only results that are PNGs
`MD5_#MD5#` can be used to search for a specific MD5
`POSTID_#` can be used to search for a specific POST ID

these can be used *the same* as tags, so let's say that you want to find all PNGs of pickles, but POST ID 23 just sucks, you're not in the mood for it, you could totally do

`pickle FILETYPE_png -POSTID_23`

and get all your pickly pics, save for Post 23 with it's terrible quality.

#### Comments
So what are those for, anyway? Well They're ***NOT*** a comments section/forum.... instead they're used for storing descriptions of your posts... BASH-Booru is a command line program, so you'll need something besides just a wall of tags to differentiate your files.

Of course, you can put mostly whatever text you want in them!

## Special Files
There are a couple of files that BASH-Booru uses that you'll need to know about

#### bbooru-file_handlers.conf
This file contains information about what commands should be used to open what types
of files you have.

Formatting Example:

| OUTPUT MODE | file extention | COMMAND %FILE% |
| --- | --- | --- |
| N | swf | firefox %FILE% |
| N | FALLBACK | xdg-open %FILE% |

without the guide it looks like this:

```
N swf firefox %FILE%
N FALLBACK xdg-open %FILE%
```

Keep in mind that `%FILE%` is replaced with the path to the file.

The filetype FALLBACK is used to open any filetype not otherwise defined in the file.
The above example opens `swf` files with Firefox and All other types of files using `xdg-open`

What do the output modes mean? They control terminal output from the programs used to open the file

| Symbol | Mode Name | What it Does |
| --- | --- | --- |
| H | Halt | Waits for program to exit, outputs normally |
| S | Standard | Outputs standard output and Standard Error |
| Q | Quiet | Outputs only Standard Error |
| N | Null | Outputs nothing |

#### bbooru-db.csv
The Bash-Booru Database file, which contains information related to all files in the `files` folder.

The formatting for this file is as follows

| Post ID | File Type | Date Added | MD5SUM | File Size | Original File Name | Source URLs | Tags | Comment |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | png | Wed Aug 23 01:05:39 2017 utc | a5373fc970393463f57116557f0146a6 | 796K | 1st Post.png  | https://derpibooru.org/1 | artist:speccysy, cloud, cute, derpibooru legacy, first fluttershy photo on derpibooru, fluttershy, flying, happy | First Fluttershy Post on the site! |

without the guide it looks like:

```"1","png","Wed Aug 23 01:05:39 2017 utc","a5373fc970393463f57116557f0146a6","796K","1st Post.png","https://derpibooru.org/1","artist:speccysy, cloud, cute, derpibooru legacy, first fluttershy photo on derpibooru, fluttershy, flying, happy","First Fluttershy Post on the site!"```

#### bbooru-tag_aliases.csv
This file contains aliases for tags. There's no built-in mechanism for modifying this file (yet), but the format is incredibly simple. And it looks like this

| To Be Replaced | To Replace with |
| --- | --- |
| nic | nicolas_cage |

which, in-file looks like `"nic","nicolas_cage"`

Aliases effect EVERYTHING from search results to adding via CSVs (See Features above)

#### bbooru-mimetypes.csv
Like other files used by BASH-Booru, this is generated by default. This is used to set the correct file extention for mimetypes... in the event you attempt to add a file with a new mimetype that BASH-Booru doesn't have on record it will ask you for the correct file extention.
Here's an example of an entry


| Mimetype | Extention |
| --- | --- |
| text/plain | txt |

in file looks like: `"text/plain","txt"`
