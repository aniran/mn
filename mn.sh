#!/usr/bin/env bash
#set -x
source ./script_ctl.src
source ./fmt_font.src    

function fn_file_exists  () { [ -f "$1" ] || msg_quit "$1: not found."; }
function get_param () {
    local param=$1; local file=$2
    fn_file_exists $file
    local loaded_param=$(grep $param $file 2>/dev/null | cut -d ' ' -f 2)
    [ -n "$loaded_param" ] && echo $loaded_param 
}

BASH_V=$(bash_version)
HOMEDIR=~
CMD_NAME=$(basename ${0%.sh})
CONFIG_FILE=$(pwd -P $0)/config
GIT_LATEST_PULL=$(pwd -P $0)/.git_latest_pull
DEFAULT_GIT_URL_MSG=INSERT_CLONE_URL

function fn_git () { git -C $DATA_DIR $*; }
function fn_check_latest_pull () {
    local secs_latest_pull=$(( $(date +"%s") - $(cat $GIT_LATEST_PULL) ))
    [ "$secs_latest_pull" -gt "$(( $GIT_PULL_INTERVAL * 3600 ))" ] \
    && fn_git pull \
    && echo $(date +"%s") > $GIT_LATEST_PULL
}

if [ -f "$CONFIG_FILE" ]; then
    DATA_DIR=$(get_param 'data_dir' $CONFIG_FILE)
    GIT_REPO=$(get_param 'git_repo' $CONFIG_FILE)
    GIT_PULL_INTERVAL=$(get_param 'pull_hours_interval' $CONFIG_FILE)
    
    if [ "$GIT_REPO" = "$DEFAULT_GIT_URL_MSG" ]; then
        msg_quit "Please specify your git_repo from $CONFIG_FILE"
    elif git -C $DATA_DIR status &>/dev/null; then
        fn_check_latest_pull
    else
        mkdir -p $DATA_DIR
        echo "Cloning $GIT_REPO to $DATA_DIR"
        [ "$(ls -A $DATA_DIR)" ] && msg_quit "$DATA_DIR is not empty, cant proceed."
        git -C $DATA_DIR clone $GIT_REPO $DATA_DIR && echo "done." 
        echo "$(date +\"%s\")" > $GIT_LATEST_PULL 
        read -n1 -p "Press any key to continue..."
    fi
else
    echo "Creating config file"
    echo -e "\
# Where your notes tags and metadata will be saved.\n\
data_dir $HOMEDIR/var/$CMD_NAME\n\
\n# Github repo URL to backup your notes.\n\
git_repo $DEFAULT_GIT_URL_MSG\n\
\n# Script wont do a git pull again until we are over this many hours from latest pull.\n\
pull_hours_interval 24" > $CONFIG_FILE \
    && echo "Done. Edit $CONFIG_FILE to setup 'git_repo' URL and 'data_dir' path."
    exit 0
fi

METADATA=$DATA_DIR/metadata     ; [ -f "$METADATA" ] || echo "index 0" > $METADATA
NOTES_DIR=$DATA_DIR/notes       ; mkdir -p $NOTES_DIR
TAGS=$DATA_DIR/tags             ; touch $TAGS
TERM_COLS=$([ -n "$COLUMNS" ] && echo $COLUMNS || tput cols)
TERM_ROWS=$([ -n "$LINES"   ] && echo $LINES   || tput lines)
BLANK_LINE="$(printf %${TERM_COLS}s)"
DEFAULT_MODE="0600"

function ff_topic   () { echo $(fmt_font bold  color white  "$1"); }
function ff_index   () { echo $(fmt_font color light_yellow "$1"); }
function ff_content () { echo $(fmt_font color dark_gray    "$1"); }
function ff_tags    () { echo $(fmt_font color cyan         "$1"); }

function fn_preview_note () { head -c $TERM_COLS $NOTES_DIR/$1 2>/dev/null; }
function fn_unique_tags  () { 
    (for ii in $(cat $TAGS | cut -d ' ' -f 2- ); do echo $ii; done;) | sort --unique 
}
function fn_unique_tags_inline () { fn_unique_tags | paste -s -; }


function fn_vcs_cmpush () { 
    local ftz=$(date +"%F %T %Z")
    fn_git add '*' \
    && fn_git commit -am "$ftz - $CMD_NAME backup." \
    && fn_git push &
}

USAGE="$(ff_topic NAME)\n\
    ${CMD_NAME} - A note-keeping script written in bash.\n\
\n$(ff_topic SYNTAX)\n\
    $CMD_NAME {new|grep|list|edit|rm}
" 
function print_usage () { echo -e "$USAGE"; }

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

function grep_tags () {
    local unique_tags="$(fn_unique_tags) "
    if [ -z "$1" ]; then :
    else
        for ii in $*; do
            [ -z "$ii" ] && continue
            unique_tags=${unique_tags//$ii/}
        done
    fi
    echo "$unique_tags"
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
    [ -s "$TAGS" ] || msg_quit "$TAGS is empty."

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
    local CUR_STR=""; local ANS=""
    while [ ! "$ANS" = $'\e' ]; do
        tput cup 0 0
        local LEN_CUR_STR=${#CUR_STR}
        echo -e "Welcome to $CMD_NAME shell. Type :q to quit, :h for instructions.\n"
        local filtered_tags="$(grep_tags $CUR_STR | paste -s -)"
        local formatted_ft=$(ff_tags "${filtered_tags}")
        echo -e "${formatted_ft}${BLANK_LINE:0:$(( ${#BLANK_LINE} - ${#filtered_tags} ))}"
        local BKIFS="$IFS"; IFS=""
        tput cup 1 0
        echo -n "$CUR_STR"
        read -d '' -n 1 ANS

        if   [ "$ANS" = $'\x0a' ]; then # ENTER
            case $CUR_STR in 
                :exit|:q|:quit) break ;;
                :help|:h) tput reset; print_usage ; read -n 1; tput reset ; CUR_STR="" ;;
            esac
        elif [ "$ANS" = $'\x20' ]; then # SPACE
            CUR_STR+=" "
        elif [ "$ANS" = $'\x7f' ]; then # BACKSPACE
            [ "$LEN_CUR_STR" -gt 0 ] && CUR_STR=${CUR_STR:0:$(( $LEN_CUR_STR - 1 ))}
            echo -ne "\b\b\b   \r$CUR_STR"
        else                            # Any other
            CUR_STR+="$ANS"
        fi
        IFS="$BKIFS"
    done
    tput reset
    echo -e "Thanks for trying!"
}

[ -z "$1" ] && mn_shell && exit 0

case $1 in
    *help)   print_usage                   ;;
    shell)   shift; mn_shell               ;;
    new)     shift; new_note $*            ;;
    grep)    shift; grep_note "$*"         ;;
    edit)    shift; edit_note "$@"         ;;
    list)    shift; list_notes             ;;
    rm)      shift; rm_note $1             ;;
    show)    shift; cat_note $1            ;;
    install) shift; fn_install             ;;
    *)       msg_quit "Invalid option: $1" ;;
esac
