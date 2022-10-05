runtime autoload/multichange/mode.vim
runtime autoload/multichange/substitution.vim

function! multichange#Setup(visual)
  call multichange#Stop()
  let b:multichange_mode = multichange#mode#New(a:visual)
  call s:ActivateCustomMappings()
  call multichange#EchoModeMessage()
endfunction

function! multichange#Start(visual)
  if !exists('b:multichange_mode')
    return
  endif

  if exists('b:multichange_last_match')
    unlet b:multichange_last_match
  endif

  let mode = b:multichange_mode

  let typeahead = s:GetTypeahead()
  let b:multichange_substitution = multichange#substitution#New(a:visual, getpos('.'))
  call feedkeys('c', 'n')
  call feedkeys(typeahead)

  let substitution = b:multichange_substitution

  if empty(substitution)
    unlet b:multichange_substitution
  else
    let match_pattern = substitution.pattern

    if mode.has_range
      let match_pattern = '\%>'.(mode.start - 1).'l'.match_pattern
      let match_pattern = match_pattern.'\%<'.(mode.end + 1).'l'
    endif

    exe '2match Search /'.escape(match_pattern, '/').'/'
  endif
endfunction

function! multichange#Substitute()
  if exists('b:multichange_mode') && exists('b:multichange_substitution')
    call s:PerformSubstitution(b:multichange_mode, b:multichange_substitution)
    unlet b:multichange_substitution
    2match none
    call multichange#EchoModeMessage()
  endif
endfunction

function! multichange#Stop()
  if exists('b:multichange_substitution')
    unlet b:multichange_substitution
    2match none
  endif

  if exists('b:multichange_mode')
    call s:DeactivateCustomMappings()
    unlet b:multichange_mode
  endif

  if exists('b:multichange_last_match')
    unlet b:multichange_last_match
  endif

  sign unplace 1
  sign unplace 2

  echo
endfunction

function! multichange#EchoModeMessage()
  if exists('b:multichange_mode')
    let message = "-- MULTI --"

    if exists('b:multichange_last_match')
      let pattern = b:multichange_last_match.pattern

      if b:multichange_last_match.count == 1
        let substitutions = "1 substitution"
      else
        let substitutions = b:multichange_last_match.count." substitutions"
      endif

      let offscreen = b:multichange_last_match.offscreen_count." offscreen"

      let message .= " (".substitutions." of ".pattern.", ".offscreen.")"
    endif

    echohl ModeMsg | echo message | echohl None
  endif
endfunction

function! s:PerformSubstitution(mode, substitution)
  try
    let saved_view = winsaveview()

    " Show the number of matches in the range
    if g:multichange_show_match_count
      let b:multichange_last_match = {}
      let b:multichange_last_match.pattern = a:substitution.pattern

      let match_count = 0
      let offscreen_count = 0

      " get the limits of the screen
      let saved_scrolloff = &scrolloff
      set scrolloff=0
      normal! H
      let screen_start = line('.')
      normal! L
      let screen_end = line('.')
      let &scrolloff = saved_scrolloff

      " start from just before the first line of the range
      if a:mode.has_range && a:mode.start > 1
        exe (a:mode.start - 1)
        normal! $
      else
        normal! G$
      endif

      " stop at end of range
      if a:mode.has_range
        let end_line = a:mode.end
      else
        let end_line = 0
      endif

      " search by wrapping (if we start at end of file), then disable wrapping
      let flags = 'w'
      while search(a:substitution.pattern, flags, end_line) > 0
        let match_count += 1

        if line('.') < screen_start || line('.') > screen_end
          let offscreen_count += 1
        endif

        let flags = 'W'
      endwhile

      call winrestview(saved_view)

      let b:multichange_last_match = {
            \ 'count':           match_count,
            \ 'offscreen_count': offscreen_count,
            \ 'pattern':         a:substitution.pattern,
            \ }
    endif

    " Build up the range of the substitution
    if a:mode.has_range
      let range = a:mode.start.','.a:mode.end
    else
      let range = '%'
    endif

    " prepare the pattern
    let pattern = escape(a:substitution.pattern, '/')

    " figure out the replacement
    let replacement = a:substitution.GetReplacement()
    if replacement == ''
      return
    endif
    let replacement = escape(replacement, '/&~\')

    " undo the last change, so the substitution applies that one as well
    undo

    " perform the substitution
    exe range.'s/'.pattern.'/'.replacement.'/ge'
  finally
    call winrestview(saved_view)
  endtry
endfunction

function! s:ActivateCustomMappings()
  let mode = b:multichange_mode

  let mode.saved_esc_mapping = maparg('<esc>', 'n')
  let mode.saved_cn_mapping  = maparg('c', 'n')
  let mode.saved_cx_mapping  = maparg('c', 'x')

  nnoremap <buffer> c :silent call multichange#Start(0)<cr>
  xnoremap <buffer> c :<c-u>silent call multichange#Start(1)<cr>
  nnoremap <buffer> <esc> :call multichange#Stop()<cr>
endfunction

function! s:DeactivateCustomMappings()
  nunmap <buffer> c
  xunmap <buffer> c
  nunmap <buffer> <esc>

  let mode = b:multichange_mode

  if mode.saved_cn_mapping != ''
    exe 'nnoremap c '.mode.saved_cn_mapping
  endif
  if mode.saved_cx_mapping != ''
    exe 'xnoremap c '.mode.saved_cx_mapping
  endif
  if mode.saved_esc_mapping != ''
    exe 'nnoremap <esc> '.mode.saved_esc_mapping
  endif
endfunction

function! s:GetTypeahead()
  let typeahead = ''

  let char = getchar(0)
  while char != 0
    let typeahead .= nr2char(char)
    let char = getchar(0)
  endwhile

  return typeahead
endfunction
