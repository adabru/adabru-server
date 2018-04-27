cli(){
  if [[ $1 == log && -n $2 ]]
  then node ./cli.js $@ | less -r +G
  else node ./cli.js $@
  fi
}
cli_complete(){
  # echo "${COMP_WORDS[1]}"
  if [[ $COMP_CWORD == 1 ]] ; then
    COMPREPLY=( $(compgen -W "start stop log ls restart" -- $2) )
  fi
  if [[ $COMP_CWORD == 2 ]] ; then
    procs=$(perl -ne "/^    \"(.+?)\": \\{/ && print \"\$1\n\"" config.json)
    COMPREPLY=( $(compgen -W "$procs ci" -- $2) )
  fi
}
complete -F cli_complete cli
