#!/usr/bin/env bash
#set -x
source ~/init_source/script_ctl.src
source ~/init_source/fmt_font.src     || msg_quit "Unable to load font formatting" 

BASH_V=$(bash_version)
HOMEDIR=~
CMD_NAME=$(basename ${0%.sh})
DATADIR=$(grep datadir $(pwd -P $0)/config 2>/dev/null | cut -d ' ' -f 2)
DATADIR=${DATADIR:-$HOMEDIR/var/$CMD_NAME} ; mkdir -p $DATADIR 
METADATA=$DATADIR/metadata     ; [ -f $METADATA ] || echo "index 0" > $METADATA
NOTES_DIR=$DATADIR/notes       ; mkdir -p $NOTES_DIR
TAGS=$DATADIR/tags             ; touch $TAGS
TERM_COLS=$([ -n "$COLUMNS" ] && echo $COLUMNS || tput cols)
DEFAULT_MODE="0600"

function ff_topic   () { echo $(fmt_font bold  color white  "$1"); }
function ff_index   () { echo $(fmt_font color light_yellow "$1"); }
function ff_content () { echo $(fmt_font color dark_gray    "$1"); }
function ff_tags    () { echo $(fmt_font color cyan         "$1"); }

function fn_file_exists  () { [ -f "$1" ] || msg_quit "$1: not found."; }
function fn_preview_note () { head -c $TERM_COLS $NOTES_DIR/$1 2>/dev/null; }

USAGE="$(ff_topic NAME)\n\
    ${CMD_NAME} - Mnemonic Notebook: A note-keeping bash script.\n\
\n$(ff_topic SYNTAX)\n\
    $CMD_NAME {new|grep|list|edit|rm}
" 
function print_usage () { echo -e "$USAGE"; }

function get_param () {
    local param=$1; local file=$2
    fn_file_exists $file
    echo $(grep $param $file 2>/dev/null || echo 0 0) | cut -d ' ' -f 2
}

function set_param () {
    local  param=$1 ; shift
    local   file=$1 ; shift
    local values="$*"
    fn_file_exists $file

    if grep -q $param $file; then
        sed -i .tmp "s/^${param} .*/${param} ${values}/g" $file 
    else
        echo "$param $values" >> $file
    fi
}

function new_note () {
    #set -x
    echo "\$1=$1"
    [ -f "$1" ] && local import_file=$1 && shift
    local new_tags="$*"

    while [ -z "$new_tags" ]; do read -p "Tags: " new_tags; done

    local index=$(get_param index $METADATA) && index=$(( $index + 1 ))
    local new_file_path=$NOTES_DIR/$index
    
    [ -n "$import_file" ] && install -m $DEFAULT_MODE $import_file $new_file_path 

    vim $new_file_path \
    && echo "Saving note $(ff_index $index): $(ff_tags $new_tags)" \
    && echo "$index $new_tags" >> $TAGS \
    && set_param index $METADATA $index 
}

function grep_note () {
    local files_list="$(ls ${NOTES_DIR}/* $TAGS)"

    for ii in "$*"; do
        files_list="$(grep $ii -l $files_list)" 
    done

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
        echo -e $(ff_content "$(fn_preview_note $index)") 
    done
    IFS="$bkifs"
    echo ""
}

function validate_note_has_tags () { grep -q "^$1 " $TAGS || msg_quit "Tags not found for $id"; }

function load_note_tags () { grep "^$1 " $TAGS | cut -d ' ' -f 2-; }

function fn_remove_tags_from () { sed -i .tmp '/^'$1' /d' $TAGS; }

function edit_note () {
    local id=$1
    local note_file_path=$NOTES_DIR/$id

    if [ -f "$note_file_path" ]; then
        validate_note_has_tags $id 
        local old_tags=$(load_note_tags $id); local new_tags=""
        
        if [ "$BASH_V" -gt "3" ]; then
            while [ -z "$new_tags" ]; do read -e -i "$old_tags" -p "Tags: " new_tags; done
        else
            echo -e "Current tags: "$(ff_tags "$old_tags")
            read -p "Type new tags or [ENTER] to keep the current: " new_tags
            [ -z "$new_tags" ] && new_tags="$old_tags"
        fi

        if [ "$new_tags" = "$old_tags" ]; then :
        else
            fn_remove_tags_from $id
            echo "$id $new_tags" >> $TAGS  # Add line with new tag set
        fi

        vim $note_file_path
    else
        msg_quit "Note $(ff_index $id) not found."
    fi
}

function cat_note () {
    local id=$1
    [ -z "$id" ] && return
    local note=$NOTES_DIR/$id
    [ -f "$note" ] && cat $note
}

function rm_note () {
    local id=$1
    [ -z "$id" ] && echo "id is empty" && list_notes && return
    local note=$NOTES_DIR/$id
    fn_remove_tags_from $id 
    [ -f "$note" ] && rm $note
    list_notes
}

function fn_install () {
    local complete_src=${CMD_NAME}.src
    ln -s $(pwd -P $0)"/$complete_src" ~/init_source/$complete_src
}

function mn_shell () {
    tput reset
    echo "Welcome to $CMD_NAME shell. Type :exit to quit, :help for instructions"
    local BKIFS="$IFS"; IFS=""; local CUR_STR=""; local ANS=""
    while [ ! "$ANS" = $'\e' ]; do
        local LEN_CUR_STR=${#CUR_STR}
        local LEN_M1=$(( $LEN_CUR_STR - 1 ))
        tput cup 0 0
        echo "Press [ESCAPE] to exit."
        echo -n "$CUR_STR"
        read -d '' -n 1 ANS
        if   [ "$ANS" = $'\x0a' ]; then break
        elif [ "$ANS" = $'\x20' ]; then CUR_STR+=" "
        elif [ "$ANS" = $'\x7f' ]; then echo -ne "\b"; [ "$LEN_M1" -gt 0 ] && CUR_STR=${CUR_STR:0:$LEN_M1}
        else CUR_STR+="$ANS"
        fi
    done
    echo -e "\n$CUR_STR"
    IFS="$BKIFS"
}

[ -z "$1" ] && mn_shell && exit 0

case $1 in
    *help)   print_usage                   ;;
    new)     shift; new_note $*            ;;
    grep)    shift; grep_note "$*"         ;;
    edit)    shift; edit_note "$@"         ;;
    list)    shift; list_notes             ;;
    rm)      shift; rm_note $1             ;;
    show)    shift; cat_note $1            ;;
    install) shift; fn_install             ;;
    *)       msg_quit "Invalid option: $1" ;;
esac
