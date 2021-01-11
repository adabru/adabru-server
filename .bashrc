cli(){
  if [[ -z "$ADABRU_SERVER_HOME" ]] ; then echo "you must set env variable ADABRU_SERVER_HOME!" ; return ; fi
  if [[ $1 == log && -n $2 ]]
  then (cd $ADABRU_SERVER_HOME && node $ADABRU_SERVER_HOME/.build/cli.js "$@" | less -r +G)
  else (cd $ADABRU_SERVER_HOME && node $ADABRU_SERVER_HOME/.build/cli.js "$@")
  fi
}
cli_complete(){
  # echo "${COMP_WORDS[1]}"
  if [[ $COMP_CWORD == 1 ]] ; then
    COMPREPLY=( $(compgen -W "start stop log ls restart config" -- $2) )
  fi
  if [[ $COMP_CWORD == 2 ]] ; then
    procs=$(perl -ne "/^  \"(.+?)\": \\{/ && print \"\$1\n\"" $ADABRU_SERVER_HOME/.config/config.json)
    COMPREPLY=( $(compgen -W "$procs" -- $2) )
  fi
  if [[ $COMP_CWORD == 3 && ${COMP_WORDS[1]} == config ]] ; then
    COMPREPLY=( $(compgen -W "get update delete" -- $2) )
  fi
}
complete -F cli_complete cli
