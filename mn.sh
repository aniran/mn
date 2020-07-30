#!/usr/bin/env bash
source ~/init_source/script_ctl.src
source ~/init_source/fmt_font.src     || msg_quit "Unable to load font formatting" 

HOMEDIR=~
CMD_NAME=$(basename ${0%.sh})
DATADIR=$HOMEDIR/var/$CMD_NAME ; mkdir -p $DATADIR 
M_NOTES=$DATADIR/m_notes       ; touch $M_NOTES
TAGS_FILE_PATH=$DATADIR/tags   ; touch $TAGS_FILE_PATH

function ff_topic ()   { echo $(fmt_font bold color white "$1"); }
function ff_index ()   { echo $(fmt_font color light_yellow "$1"); }
function ff_content () { echo $(fmt_font color dark_gray "$1"); }
function ff_tags  ()   { echo $(fmt_font color cyan "$1"); }

USAGE="$(ff_topic NAME)\n\
    ${CMD_NAME} - Mnemonic Notebook: manage snippets using simple CLI tools.\n\
\n$(ff_topic SYNTAX)\n\
    $CMD_NAME {new|grep|list|edit|rm}
" 
function print_usage () { echo -e "$USAGE"; }

function get_param () {
    local param=$1; local file=$2
    [ -f "$file" ] || msg_quit "$file: not found."
    echo $(grep $param $file 2>/dev/null || echo 0 0) | cut -d ' ' -f 2
}

function set_param () {
    local param=$1; local value=$2; local file=$3
    [ -f "$file" ] || msg_quit "$file: not found."
    grep -q $param $file && sed -i "s/^${param}/${param} ${value}/g" $file \
        || echo "$param $value" >> $file
}

function add_note_tags () { echo "$1 $2"     >> $TAGS_FILE_PATH; }
function del_note_tags () { sed "/^$note /d" -i $TAGS_FILE_PATH; }

function new_note () {
    while [ -z $TAGS ]; do read -p "Tags: " TAGS; done

    local index=$(get_param index $M_NOTES) && index=$(( $index + 1 ))
    local new_file=note.${index}.txt
    local new_file_path=$DATADIR/$new_file
    vim $new_file_path \
        && echo "Saving $new_file" \
        && add_note_tags $new_file $TAGS \
        && set_param index $index $M_NOTES
}

#function grep_note () {
#    local pattern="${1// /\\|}"
#
#    for ii in $(grep -l $pattern $DATADIR/note.* $TAGS_FILE_PATH); do
#        local index=$(basename ${ii%.txt}); index=${index#note.}
#        echo -e $(ff_index $index)":"
#        grep -h --color=auto $pattern $ii
#        echo ""
#    done
#}

function grep_note () {
    # Build list of all our notes and tags
    local files_list="$(ls $DATADIR/note.* $TAGS_FILE_PATH)"

    # Drill down files containing all words 
    for ii in $1; do
        files_list="$(grep $ii -l $files_list)" 
    done

    # Showing what we got 
    local pattern="${1// /\\|}"

    for ii in $files_list; do
        local index=$(basename ${ii%.txt}); index=${index#note.}
        echo -e $(ff_index $index)":"
        grep -h --color=auto $pattern $ii
        echo ""
    done
}

function list_notes () {
    local term_cols=$([ -z "$COLUMNS" ] && echo $COLUMNS || tput cols)
    for ii in "$(cat $TAGS_FILE_PATH)"; do
        local index=$(echo $ii | cut -d ' ' -f 1 | cut -d . -f 2)
        local tags=$(echo $ii | cut -d ' ' -f 2-)
        echo "note.$(ff_index $index): "$(ff_tags "$tags")
        echo -e $(ff_content "$(head -c $term_cols $DATADIR/note.${index}.txt)")
        echo ""
    done
}

function validate_note_has_tags () {
    grep -q $1 $TAGS_FILE_PATH || msg_quit "Tags not found for $id"
}

function load_note_tags () {
    grep "note.${1}.txt" $TAGS_FILE_PATH | cut -d ' ' -f 2-
}

function edit_note () {
    local id=$1
    local note="note.${1}.txt" 
    local note_file_path=$DATADIR/$note

    if [ -f "$note_file_path" ]; then
        validate_note_has_tags $note 
        local old_tags=$(load_note_tags $id); local new_tags=""
        
        while [ -z "$new_tags" ]; do read -e -i "$old_tags" -p "Tags: " new_tags; done

        if [ "$new_tags" = "$old_tags" ]; then :
        else
            del_note_tags $note
            add_note_tags $note "$new_tags"
        fi

        vim $note_file_path
    else
        msg_quit "Note $note not found."
    fi
}

[ -z "$1" ] && print_usage && exit 1

case $1 in
    *help) print_usage ;;
    new)   new_note ;;
    grep)  shift; grep_note "$*" ;;
    edit)  shift; edit_note "$@" ;;
    list)  shift; list_notes ;;
    *)     msg_quit "Invalid option: $1" ;;
esac
