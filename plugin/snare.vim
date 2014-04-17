" Snippets Again, with Regular Expressions.
" Author:  Paul Isambert (zappathustra AT free DOT fr)
" Version: 1.0 - April 2014

" Options. {{{
" Default values. {{{
let s:defaults = {}
let s:defaults.path       = expand("<sfile>:h") . "/snare"
let s:defaults.magic      = '\v'
let s:defaults.before     = '^\s{-}\zs'
let s:defaults.after      = '$'
let s:defaults.dummy      = '\v\$%(\((.{-})\))?\$'
let s:defaults.submatch   = '\v\\(\d)'
let s:defaults.linebreak  = ''
let s:defaults.noline     = '\v^$'
let s:defaults.substitute = '\v`(.{-})`'
function! s:defaults.eval (str)
  exe "return " . a:str
endfunction
" }}}
" s:get (option) -- Get the value of {option} either as set for the current filetype or the default. {{{
function! s:get (option)
  if has_key(s:snares, &ft) && has_key(s:snares[&ft].options, a:option)
    return s:snares[&ft].options[a:option]
  elseif has_key(g:snare, a:option)
    return g:snare[a:option]
  else
    return s:defaults[a:option]
  endif
endfunction
" }}}
" }}}

" Getting the script number. Must be done in a function for <sfile> to be right. {{{
function! s:getSID ()
  let s:SID = matchstr(expand('<sfile>'), '<SNR>\d\+_\ze.*SID$')
endfunction
call s:getSID()
" }}}

" snare#load ([noforce]) -- Load snares for the current filetype, no reload if {noforce}. {{{
let s:snares = {}
function! snare#load (...)
  if (!has_key(s:snares, &ft) || !a:0 || !a:1)
    let p = has_key(g:snare, "path") ? g:snare.path : s:defaults.path
    let p = expand(p . "/" . &ft . ".snare")
    if filereadable(p)
      let lines = readfile(p)

      " Retrieving local options. {{{
      let s:snares[&ft] = {"options": {}}
      let i = 0
      while lines[i] =~ "^$"
        let i += 1
      endwhile
      if lines[i] =~ "^options$"
        let i += 1
        while i < len(lines) && lines[i] !~ "^endoptions$"
          let i += 1
        endwhile
        if i == len(lines)
          echoerr "Missing `endoptions' in `" . &ft . ".snare'. Snares won't be loaded."
          return
        endif

        " Take the first i lines, removing 'options' and 'endoptions'.
        let options = remove(lines, 0, i)
        call remove(options, -1)
        call remove(options, 0)
        for o in options
          let m = matchlist(o, '\v^\s*(.{-})\s*:\s*(.{-})\s*$')
          if len(m)
            let [k, v] = m[1:2]
            let s:snares[&ft].options[k] = v
          endif
        endfor
      endif
      " }}}

      " Retrieving snares. {{{
      let patterns = []
      let state = 0
      for line in lines
        " Empty line.
        if !len(line)
          if state
            call insert(patterns, current)
            let state = 0
          endif
        " Replacement.
        elseif state
          call add(current.lines, line)
        " Pattern.
        else
          let current = {"pattern": s:get("magic") . s:get("before") . line . s:get("after"), "lines": []}
          let state = 1
        endif
      endfor
      " If the file doesn't end with a blank line, there is an unstored snare.
      if state
        call insert(patterns, current)
      endif
      let s:snares[&ft].patterns = patterns
      " }}}

    endif
  endif
endfunction
" }}}

" snare#trigger (rhs) -- Used in mapping. {{{
function! snare#trigger (rhs, ...)
  call snare#load(1)
  if has_key(s:snares, &ft)
    let snares = s:snares[&ft]
    for action in a:000
      if action ==# "expand"
        let line = getline(".")
        let c = col(".")-1
        let [s:before, s:after] = [c ? line[0:c-1]  : "", line[c :]]
        for i in range(0, len(snares.patterns)-1)
          if match(s:before, snares.patterns[i].pattern)+1
            let &undolevels = &undolevels " To break undo.
            return "\<Esc>:call " . s:SID . "expand(" . i . ")\<CR>"
          endif
        endfor

      elseif action ==# "next" || action ==# "prev"
        call s:search(action ==# "prev")
        if s:p[0]
          return "\<Esc>:call " . s:SID . "dummy()\<CR>"
        endif

      endif
    endfor
  endif
  return a:rhs
endfunction
" }}}

" s:search (backward) -- Finds a dummy, possibly {backward}. {{{
function! s:search (backward)
  let s:p = searchpos(s:get("dummy"), 'cn' . (a:backward ? "b" : ""))
endfunction
" }}}

" s:expand (match) -- Expands a snare. {{{
function! s:expand (i)
  let snare = s:snares[&ft].patterns[a:i]
  let matches = matchlist(s:before, snare.pattern)
  let replacement = []

  for i in range(0, len(snare.lines)-1)
    let ll = s:prepare_line(snare.lines[i], matches)
    if !i " First line of the replacement text.
      let ll[0] = substitute(s:before, snare.pattern, substitute(ll[0], '\\', '\\\\', 'g'), "")
      let indent = matchstr(ll[0], '^\s*')
    endif
    for l in ll
      if match(l, s:get("noline")) < 0
        call add(replacement, l)
      endif
    endfor
  endfor
  for i in range(1, len(replacement)-1)
    let replacement[i] = indent . replacement[i]
  endfor
  let length = len(replacement[-1])
  let replacement[-1] .= s:after

  let ln   = line(".")
  exe ln . "delete _"

  call append(ln-1, replacement)
  call cursor(ln, 1)
  call s:search(0)
  if s:p[0]
    call s:dummy()
  else
    call cursor(ln+len(replacement)-1, length)
    if len(s:after)
      normal! l
      startinsert
    else
      startinsert!
    endif
  endif
endfunction
" }}}

" s:prepare_line (line, matches) -- Replace submatches and executable parts. {{{
function! s:prepare_line (line, matches)
  let l = substitute(a:line, s:get("submatch"), '\=submatch(1) < len(a:matches) ? a:matches[submatch(1)] : ""', 'g')
  " We can't really use s:get() here, because passing functions around
  " is a bit of a pain.
  if has_key(s:snares[&ft].options, "eval")
    let fun = "function(s:snares[&ft].options.eval)"
  elseif has_key(g:snare, "eval")
    let fun = "g:snare.eval"
  else
    let fun = "s:defaults.eval"
  endif
  let l = substitute(l, s:get("substitute"), '\=' . fun . '(submatch(1))', 'g')
  let lb = s:get("linebreak")
  " split("", pat) returns an empty List, but we want [""].
  if match(l, '.')+1 && lb !~ '^$'
    let ll = split(l, lb)
  else
    let ll = [l]
  endif
  return ll
endfunction
" }}}

" s:dummy () -- Jump to a dummy. {{{
function! s:dummy ()
  let line = getline(s:p[0])
  let dummy = s:get("dummy")
  let m = escape(matchlist(line, dummy)[1], '\')
  call cursor(s:p)
  let newline = substitute(line, dummy, m, '')
  call setline(s:p[0], newline)
  let s = 'normal! /\V\%#' . m
  if len(m)
    exe s . "\<CR>gn\<C-G>"
  else
    exe s
    if substitute(line, dummy . '\m$', "", "") ==# newline
      " The match was at the end of the line.
      startinsert!
    else
      startinsert
    endif
  endif
endfunction
" }}}

" vim: set foldmethod=marker:
