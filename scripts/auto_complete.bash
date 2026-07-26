# usage: source auto_complete.bash

COMMANDS="start start_gpu enter remove stopall install_core bootstrap build install init profile usage -h --help"

function _complete_func() {
    COMPREPLY=()
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmds="$(echo ${COMMANDS} | xargs)"

    COMPREPLY=($(compgen -W "${cmds}" -- ${cur}))

}

complete -F _complete_func -o default aem
