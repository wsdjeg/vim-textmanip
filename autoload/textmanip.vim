" Util:
let s:u = textmanip#util#get()

function! s:error(desc, expr) "{{{1
  if a:expr
    throw "CANT_MOVE " . a:desc
  endif
endfunction
"}}}

" Main:
let s:Textmanip = {}

function! s:Textmanip.start(env) "{{{1
  try
    let shiftwidth = g:textmanip_move_ignore_shiftwidth
          \ ? g:textmanip_move_shiftwidth
          \ : &shiftwidth

    let options = textmanip#options#replace({'&virtualedit': 'all', '&shiftwidth': shiftwidth })
    call textmanip#selection#new(a:env).manip()
  catch /FINISH/
  catch /CANT_MOVE/
    normal! gv
  finally
    call options.restore()
  endtry
endfunction

function! s:Textmanip.init(env) "{{{1
  let [s, e] = s:getpos(a:env.mode)
  let pos_s  = textmanip#pos#new(s)
  let pos_e  = textmanip#pos#new(e)
  let self.varea  = textmanip#selection#new(pos_s, pos_e, a:env)
  let self.env = a:env

  let action = self.env.action
  if self.env.mode ==# 'n' || action ==# 'blank'
        \ || (action ==# 'dup' && self.env.emode  ==# 'insert' )
        \ || self.env.dir =~# 'v\|>'
    return
  endif

  return
  call self.adjust_count() 
  let dir = self.env.dir
  let linewise = self.varea.linewise

  try
    call s:error("Topmost line",
          \ dir ==# '^' && self.varea.pos.T.line ==# 1
          \ )
    call s:error( "all line have no-blank char",
          \ dir ==# '<' && linewise &&
          \ empty(filter(self.varea.yank().content, "v:val =~# '^\\s'"))
          \ )
    call s:error( "no space to left",
          \ self.env.dir ==# '<' && !linewise &&
          \ self.varea.pos.L.colm == 1 && self.env.mode ==# "\<C-v>"
          \ )
    call s:error("count 0", self.env.count ==# 0 )
  endtry
endfunction

function! s:Textmanip.adjust_count() "{{{1
  let dir = self.env.dir

  if dir ==# '^'
    let max = self.varea.pos.T.line - 1
  elseif dir ==# '<'
    if self.varea.linewise
      let max = self.env.count
    else
      let max = self.varea.pos.L.colm  - 1
    endif
  endif

  if self.env.emode ==# 'replace' && self.env.action ==# 'dup'
    if     dir ==# '^' | let max = max / self.varea.height
    elseif dir ==# '<' | let max = max / self.varea.width
    endif
  endif
  let self.env.count = min([max, self.env.count])
endfunction

function! s:Textmanip.kickout(num, guide) "{{{1
  " FIXME
  let orig_str = getline(a:num)
  let s1       = orig_str[ : col('.')- 2 ]
  let s2       = orig_str[ col('.')-1 : ]
  let pad      = &textwidth - len(orig_str)
  let pad      = ' ' . repeat(a:guide, pad - 2) . ' '
  let new_str  = join([s1, pad, s2],'')
  return new_str
endfunction
"}}}

" API:
function! textmanip#start(action, dir, mode, emode) "{{{1
  let action = a:action ==# 'move1' ? 'move' : a:action

  try
    if a:action ==# 'move1'
      let _ignore_shiftwidth  = g:textmanip_move_ignore_shiftwidth
      let _shiftwidth         = g:textmanip_move_shiftwidth
      let g:textmanip_move_ignore_shiftwidth = 1
      let g:textmanip_move_shiftwidth        = 1
    endif

    let env = {
          \ "action": action,
          \ "dir": a:dir,
          \ "mode": a:mode ==# 'x' ? visualmode() : a:mode,
          \ "emode": (a:emode ==# 'auto') ? g:textmanip_current_mode : a:emode,
          \ "count": v:count1,
          \ }
    call s:Textmanip.start(env)

  finally
    if a:action ==# 'move1'
      let g:textmanip_move_ignore_shiftwidth = _ignore_shiftwidth
      let g:textmanip_move_shiftwidth        = _shiftwidth
    endif
  endtry
endfunction

" [FIXME] very rough state.
function! textmanip#kickout(guide) range "{{{1
  " let answer = a:ask ? input("guide?:") : ''
  let guide = !empty(a:guide) ? a:guide : ' '
  let orig_pos = getpos('.')
  if a:firstline !=# a:lastline
    normal! gv
  endif
  for n in range(a:firstline, a:lastline)
    call setline(n, s:Textmanip.kickout(n, guide))
  endfor
  call setpos('.', orig_pos)
endfunction


function! textmanip#mode(...) "{{{1
  if a:0 ==# 0
    return g:textmanip_current_mode
  endif

  let g:textmanip_current_mode =
        \ g:textmanip_current_mode ==# 'insert' ? 'replace' : 'insert'
  echo "textmanip-mode: " . g:textmanip_current_mode
endfunction
"}}}

" vim: foldmethod=marker
