cli(){
  if [[ $1 == log && -n $2 ]]
  then node ./.build/cli.js $@ | less -r +G
  else node ./.build/cli.js $@
  fi
}
cli_complete(){
  # echo "${COMP_WORDS[1]}"
  if [[ $COMP_CWORD == 1 ]] ; then
    COMPREPLY=( $(compgen -W "start stop log ls restart config" -- $2) )
  fi
  if [[ $COMP_CWORD == 2 ]] ; then
    if [[ ${COMP_WORDS[1]} == config ]] ; then
      COMPREPLY=( $(compgen -W "processes webhooks vars" -- $2) )
    else
      procs=$(perl -ne "/^    \"(.+?)\": \\{/ && print \"\$1\n\"" .config/config.json)
      COMPREPLY=( $(compgen -W "$procs ci" -- $2) )
    fi
  fi
  if [[ $COMP_CWORD == 3 && ${COMP_WORDS[1]} == config ]] ; then
    COMPREPLY=( $(compgen -W "get update delete" -- $2) )
  fi
}
complete -F cli_complete cli
