#!/usr/bin/env bash
#set -x
source ~/init_source/script_ctl.src
source ~/init_source/fmt_font.src     || msg_quit "Unable to load font formatting" 

HOMEDIR=~
CMD_NAME=$(basename ${0%.sh})
DATADIR=$HOMEDIR/var/$CMD_NAME ; mkdir -p $DATADIR 
METADATA=$DATADIR/metadata     ; [ -f $METADATA ] || echo "index 0" > $METADATA
NOTES_DIR=$DATADIR/notes       ; mkdir -p $NOTES_DIR
TAGS=$DATADIR/tags             ; touch $TAGS
TERM_COLS=$([ -z "$COLUMNS" ] && echo $COLUMNS || tput cols)

function ff_topic ()   { echo $(fmt_font bold color white "$1"); }
function ff_index ()   { echo $(fmt_font color light_yellow "$1"); }
function ff_content () { echo $(fmt_font color dark_gray "$1"); }
function ff_tags  ()   { echo $(fmt_font color cyan "$1"); }

function fn_check_file_exists () { [ -f "$1" ] || msg_quit "$1: not found."; }

USAGE="$(ff_topic NAME)\n\
    ${CMD_NAME} - Mnemonic Notebook: manage snippets using simple CLI tools.\n\
\n$(ff_topic SYNTAX)\n\
    $CMD_NAME {new|grep|list|edit|rm}
" 
function print_usage () { echo -e "$USAGE"; }

function get_param () {
    local param=$1; local file=$2
    fn_check_file_exists $file
    echo $(grep $param $file 2>/dev/null || echo 0 0) | cut -d ' ' -f 2
}

function set_param () {
    local  param=$1 ; shift
    local   file=$1 ; shift
    local values="$*"
    fn_check_file_exists $file

    if grep -q $param $file; then
        sed -i .tmp "s/^${param} .*/${param} ${values}/g" $file 
    else
        echo "$param $values" >> $file
    fi
}

function add_note_tags () { echo "$1 $2"     >> $TAGS; }
function del_note_tags () { sed "/^$note /d" -i $TAGS; }

function new_note () {
    local new_tags="$*"
    while [ -z "$new_tags" ]; do read -p "Tags: " new_tags; done

    local index=$(get_param index $METADATA) && index=$(( $index + 1 ))
    local new_file_path=$NOTES_DIR/$index

    vim $new_file_path \
        && echo "Saving note $(ff_index $index): $(ff_tags $new_tags)" \
        && echo "$index $new_tags" >> $TAGS \
        && set_param index $METADATA $index 
}

#function grep_note () {
#    local pattern="${1// /\\|}"
#
#    for ii in $(grep -l $pattern $DATADIR/note.* $TAGS); do
#        local index=$(basename ${ii%.txt}); index=${index#note.}
#        echo -e $(ff_index $index)":"
#        grep -h --color=auto $pattern $ii
#        echo ""
#    done
#}

function grep_note () {
    # Build list of all our notes and tags
    local files_list="$(ls ${NOTES_DIR}/* $TAGS)"

    # Drill down files containing all words 
    for ii in "$*"; do
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
    [ -s "$TAGS" ] || return

    local bkifs="$IFS"
    IFS=$'\n'
    for ii in $(cat $TAGS); do
        local index=${ii%% *}
        local tags=${ii#* }
        echo "$(ff_index $index): "$(ff_tags "$tags")
        echo -e $(ff_content "$(head -c $TERM_COLS $NOTES_DIR/${index} 2>/dev/null)")
        echo ""
    done
    IFS="$bkifs"
}

function validate_note_has_tags () {
    grep -q $1 $TAGS || msg_quit "Tags not found for $id"
}

function load_note_tags () {
    grep "note.${1}.txt" $TAGS | cut -d ' ' -f 2-
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
        msg_quit "Note $(ff_index $id) not found."
    fi
}

function rm_note () {
    [ -z "$1" ] && list_notes && return
}

[ -z "$1" ] && print_usage && exit 1

case $1 in
    *help) print_usage                   ;;
    new)   shift; new_note "$*"          ;;
    grep)  shift; grep_note "$*"         ;;
    edit)  shift; edit_note "$@"         ;;
    list)  shift; list_notes             ;;
    rm)    shift; rm_note                ;;
    *)     msg_quit "Invalid option: $1" ;;
esac
