" BlockMoveSummary:
"======================= {{{
"  c = 1
"  a  = [1, 2, 3]
" Up:
"  a[     : c-1 ] = [1]
"  a[   c :     ] = [2, 3]
"  a[   c :     ] + a[   : c-1 ] = [2, 3, 1]
"
" Down:
"  a[  -1 :     ] = [3]
"  a[     : -2  ] = [1, 2]
"  a[  -1 :     ] + a[   :   -2] = [3, 1, 2]
"
"}}}
" Up_or_Left:
"======================= {{{
"
"    Line                      index
"        +-----------------+   -+-
"     1  |   Replaced      | 0  | count amount
"        +-----------------+   -+-(1 in this example)
"     2  |                 | 1  |
"        +   Original      +    | height
"     3  |   Selection     | 2  |
"        +-----------------+   -+-
"                |
"                | let s = getline(1, 3)
"                |
"                V
"  index    0      1      2            1      2      0
"  idx rev -3     -2     -1           -2     -1     -3
"       +======+------+------+     +------+------+======+
"       |  L1  |  L2  |  L3  | =>  |  L2  |  L3  |  L1  |
"       +======+------+------+     +------+------+======+
"       |-count|--- height---|     |--- height---|-count|
"       s[:c-1]|   s[c:]     |     |   s[c:]  +   s[:c-1]
"       |  |   |      |      |     |      |      |  |   |
"       |  V   |      V      |     |      V      |  V   |
"       |s[:0] |    s[1:]    | =>  |    s[1:]    |s[:0] |
"
"
" "}}}
" Down:
"======================= {{{
"    Line                      index
"        +-----------------+   -+-
"     1  |   Original      | 0  |
"        +   Selection     +    | height
"     2  |                 | 1  |
"        +-----------------+   -+-
"     3  |   Replaced      | 2  | count amount
"        +-----------------+   -+-(1 in this example)
"                |
"                | let s = getline(1, 3)
"                |
"                V
"  index    0      1      2           2      0      1
"  idx rev -3     -2     -1          -1     -3     -2
"       +------+------+======+    +======+------+------+
"       |  L1  |  L2  |  L3  | => |  L3  |  L1  |  L2  |
"       +------+------+======+    +======+------+------+
"       |--- height---|-count|    |-count|--- height---|
"       | s[0:-c-1]   |s[-c:]|    |s[-c:]|  s[ :-c-1]  |
"       |      |      |  |   |    |      |             |
"       |      V      |  V   |    |      |             |
"       | s[0:-2]     |s[-1:]| => |s[-1:]+  s[ :-2]    |
"}}}
" VisualArea:
"=====================
let s:textmanip = {}
function! s:textmanip.setup() "{{{
    " call self.shiftwidth_switch()
    call self.virtualedit_start()
    if ! textmanip#status#undojoin()
      let b:textmanip_replaced = textmanip#replaced#new(self)
    endif
    let self._replaced = b:textmanip_replaced
endfunction "}}}
function! s:textmanip.finish() "{{{
    call self.virtualedit_restore()
    call textmanip#status#update()
    " call self.shiftwidth_restore()
endfunction "}}}
function! s:textmanip.move(direction) "{{{
  try
    if self.cant_move
      normal! gv
      return
    endif
    call self.setup()
    call self.extend_EOF()

    if self.is_linewise
      call self.move_line()
    else
      call self.move_block()
    endif
    " [FIXME] dirty hack for status management yanking let '< , '> refresh,
    " use blackhole @_ register
    normal! "_ygv
  finally
    call self.finish()
  endtry
endfunction "}}}

function! s:textmanip.move_block() "{{{
  if s:textmanip_current_mode ==# "insert"
    call self.varea._move_block_insert(self.direction, self._count)
  elseif s:textmanip_current_mode ==# "replace"
    call self.varea
          \._move_block_replace(self.direction, self._count, self._replaced)
  endif
endfunction "}}}

function! s:textmanip.move_line() "{{{
  let c = self._count
  if self.direction =~# '\v^(right|left)$'
    let ward = {'right': ">", 'left': "<" }[self.direction]
    exe "'<,'>" . repeat(ward, c)
    call self.varea.select()
    return
  endif

  if s:textmanip_current_mode ==# "insert"
    let [ chg, last ] =
          \ self.direction ==# "up"   ? ['u-1, ', 'd-1, ' ]:
          \ self.direction ==# "down" ? ['d+1, ', 'u+1, ' ]: throw

    "(u)_rotate
    let meth = self.direction[0] . "_rotate"
    let replace  = textmanip#area#new(
          \ self.varea.move(chg).content().content
          \ )[meth](c).data()
    call setline(self.varea.u.line(), replace)
    call self.varea.move(last).select()

  elseif s:textmanip_current_mode ==# "replace"
    let ul = self.varea.u.line()
    let dl = self.varea.d.line()
    let [ replace_line, set_line, replace_rule, last ] =  {
          \ "up":   [ ul-c, ul-c, "selected + rest",  ['u-1, ','d-1, ']],
          \ "down": [ dl+c, ul  , "rest + selected",  ['u+1,', 'd+1, ']],
          \ }[self.direction]
    let selected = self.varea.content().content
    let rest     = self._replaced[self.direction](getline(replace_line))
    call setline(set_line, eval(replace_rule))
    call self.varea.move(last).select()
  endif
endfunction "}}}

function! s:textmanip.shiftwidth_switch() "{{{
  let self._shiftwidth = &sw
  let &sw = g:textmanip_move_ignore_shiftwidth
        \ ? g:textmanip_move_shiftwidth : &sw
endfunction "}}}
function! s:textmanip.shiftwidth_restore() "{{{
  let &sw = self._shiftwidth
endfunction "}}}

function! s:textmanip.duplicate_block() "{{{
  call self.virtualedit_start()

  let c       = self._prevcount
  let h       = self.height
  let selected = self.varea.content()
  let selected.content =
        \ textmanip#area#new(selected.content).v_duplicate(c).data()

  if s:textmanip_current_mode ==# "insert"
    let blank_lines = map(range(h*c), '""')

    let ul = self.varea.u.line()
    let dl = self.varea.d.line()
    let [ blank_target, chg, last ] =  {
          \ "up":   [ ul-1, '', 'd+'.(h*c-h).', ' ],
          \ "down": [ dl  , ['u+'. h .', ', 'd+'.(h*c).', '], ''],
          \ }[self.direction]
    call append(blank_target, blank_lines)
    call self.varea.move(chg).select().paste(selected).select()

  elseif s:textmanip_current_mode ==# "replace"
    let chg =  {
          \ "up":   ['u-' . (h*c) . ', ', 'd-' . h . ', '],
          \ "down": ['u+' . h . ', ', 'd+'.(h*c).', ' ],
          \ }[self.direction]
    call self.varea.move(chg).select().paste(selected).select()
  endif

  call self.virtualedit_restore()
endfunction "}}}

function! s:textmanip.duplicate_line(mode) "{{{
  if a:mode ==# 'n'
    " normal
    let c     = self._count
    let line  = self.cur_pos.line()
    let col   = self.cur_pos.col()
    let lines = textmanip#area#new(getline(line,line)).v_duplicate(c).data()
    let [target_line, last_line ] =
          \ self.direction ==# 'up'   ? [line-1, line    ] :
          \ self.direction ==# 'down' ? [line  , line + c] : throw
    call append(target_line, lines)
    call cursor(last_line, col)
  else
    " visual
    let c        = self._prevcount
    let h        = self.height
    let selected = self.varea.content().content
    let append   = textmanip#area#new(selected).v_duplicate(c).data()

    let [target_line, last ] = {
          \ "up":   [ self.varea.u.line() -1 , 'd+' . (h*c-h) . ', ' ],
          \ "down": [ self.varea.d.line() ,['u+' . h . ', ', 'd+'.(h*c).', '] ],
          \ }[self.direction]

    call append(target_line , append)
    call self.varea.move(last).select()
  end
endfun "}}}
function! s:textmanip.init(direction, mode) "{{{
  let self.direction = a:direction
  let self.mode       = a:mode ==# 'v' ? visualmode() : 'n'
  let p               = getpos('.')
  let self.cur_pos    = textmanip#pos#new([p[1], p[2] + p[3]])
  let self._count     = v:count1
  let self._prevcount = (v:prevcount ? v:prevcount : 1)
  if a:mode ==# 'n' | return | endif
  " throw self.mode

  let self.varea  = self.preserve_selection(self.mode)
  let self.width  = self.varea.width
  let self.height = self.varea.height

  let self.is_linewise = (self.mode ==# 'V' )
        \ || (self.mode ==# 'v' && self.height > 1)

  " adjust count
  let max = self._count
  if self.direction ==# 'up'
    let max = self.varea.u.line() - 1
  elseif self.direction ==# 'left' && !self.is_linewise
    let max = self.varea.u.col() - 1
  endif
  let self._count = min([max, self._count])

  let self.cant_move = 0
  try
    if self.direction ==# 'up'
      if self.varea.u.line() ==# 1
        throw "CANT_MOVE"
      endif
    elseif self.direction ==# 'left'
      if self.is_linewise
        if empty(filter(self.varea.content().content, "v:val =~# '^\\s'"))
          throw "CANT_MOVE"
        endif
      else
        if self.varea.u.col() == 1 && self.mode ==# "\<C-v>"
          throw "CANT_MOVE"
        endif
      endif
    endif
  catch /CANT_MOVE/
    let self.cant_move = 1
  endtry
endfunction "}}}
function! s:textmanip.preserve_selection(mode) "{{{
  " current pos
  exe 'normal! gvo' | let s = getpos('.') | exe "normal! " . "\<Esc>"
  exe 'normal! gvo' | let e = getpos('.') | exe "normal! " . "\<Esc>"
" getpos() return [bufnum, lnum, col, off]
" off is offset from actual col when virtual edit(ve) mode,
" so, to respect ve position, we sum "col" + "off"
  return textmanip#selection#new(
        \ [s[1], s[2] + s[3]], [e[1], e[2] + e[3]], a:mode )
endfunction "}}}
function! s:textmanip.extend_EOF() "{{{
  " even if set ve=all, dont automatically extend EOF
  let amount = (self.varea.d.line() + self._count) - line('$')
  if self.direction ==# 'down' && amount > 0
    call append(line('$'), map(range(amount), '""'))
  endif
endfunction "}}}
function! s:textmanip.virtualedit_start() "{{{
  let self._virtualedit = &virtualedit
  let &virtualedit = 'all'
endfunction "}}}
function! s:textmanip.virtualedit_restore() "{{{
  let &virtualedit = self._virtualedit
endfunction "}}}
function! s:textmanip.dump() "{{{
  echo PP(self.__table)
endfunction "}}}
" }}}
" Other:
"===================== {{{
function! s:textmanip.kickout(num, guide) "{{{
  let orig_str = getline(a:num)
  let s1 = orig_str[ : col('.')- 2 ]
  let s2 = orig_str[ col('.')-1 : ]
  let pad = &textwidth - len(orig_str)
  let pad = ' ' . repeat(a:guide, pad - 2) . ' '
  let new_str = join([s1, pad, s2],'')
  return new_str
endfunction "}}}
" }}}

" PlublicInterface:
"===================== {{{
function! textmanip#do(action, direction, mode, ...) "{{{
  call s:textmanip.init(a:direction, a:mode)
  let s:textmanip_current_mode = ( a:0 > 0 ) ? a:1 : g:textmanip_current_mode

  if a:action ==# 'move'
    call s:textmanip.move(a:direction)
  elseif a:action ==# 'dup'
    if char2nr(visualmode()) ==# char2nr("\<C-v>") ||
          \ s:textmanip.mode ==# 'v' && !s:textmanip.is_linewise
      call s:textmanip.duplicate_block()
    else
      call s:textmanip.duplicate_line(a:mode)
    endif
  endif
endfunction "}}}

function! textmanip#do1(action, direction, mode) "{{{
  try
    let _textmanip_move_ignore_shiftwidth = g:textmanip_move_ignore_shiftwidth
    let _textmanip_move_shiftwidth        = g:textmanip_move_shiftwidth

    let g:textmanip_move_ignore_shiftwidth = 1
    let g:textmanip_move_shiftwidth        = 1
    call textmanip#do(a:action, a:direction, a:mode)
  finally
    let g:textmanip_move_ignore_shiftwidth = _textmanip_move_ignore_shiftwidth
    let g:textmanip_move_shiftwidth        = _textmanip_move_shiftwidth
  endtry
endfunction "}}}

" [FIXME] very rough state.
function! textmanip#kickout(guide) range "{{{
  " let answer = a:ask ? input("guide?:") : ''
  let guide = !empty(a:guide) ? a:guide : ' '
  let orig_pos = getpos('.')
  if a:firstline !=# a:lastline
    normal! gv
  endif
  for n in range(a:firstline, a:lastline)
    call setline(n, s:textmanip.kickout(n, guide))
  endfor
  call setpos('.', orig_pos)
endfunction "}}}

function! textmanip#toggle_mode() "{{{
  let g:textmanip_current_mode =
        \ g:textmanip_current_mode ==# 'insert'
        \ ? 'replace' : 'insert'
  echo "textmanip-mode: " . g:textmanip_current_mode
endfunction "}}}

function! textmanip#mode() "{{{
  return g:textmanip_current_mode
endfunction "}}}

function! textmanip#debug() "{{{
  return PP(s:textmanip._replaced._data)
endfunction "}}}
" }}}
"
" vim: foldmethod=marker
