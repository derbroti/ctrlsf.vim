" ============================================================================
" Description: An ack/ag/pt/rg powered code search and view tool.
" Author: Ye Ding <dygvirus@gmail.com>
" Licence: Vim licence
" Version: 2.6.0
" ============================================================================

let s:rendered_par = 0
let s:rendered_match = 0
let s:cur_file = ''
let s:procbar_idx = 0
"let s:procbar_spinner = ['|' , '/', '-' , '\']
let s:procbar_spinner = ['⠋', '⠙', '⠸', '⠴', '⠦', '⠇']

func! s:SummaryMatch() abort
    let files   = len(ctrlsf#db#FileResultSet())
    let matches = len(ctrlsf#db#MatchList())
    return printf("%s matches in %s files", matches, files)
endf

func! s:SummaryState(procbar) abort
    if a:procbar == 100 || a:procbar == 0
        return "Done"
    elseif a:procbar == -1
        return "Cancelled"
    else
        return printf("Searching %s", s:procbar_spinner[a:procbar - 1])
    endif
endf


func! s:Filename(paragraph) abort
    return fnamemodify(a:paragraph.filename, ':p:~:.')
endf

func! s:Line(line) abort
    let out  = a:line.lnum
    let out  = repeat(' ', ctrlsf#view#Indent() - len(out) - 1) . out . ' '
    return [out, a:line.content]
endf

func! s:LineCompact(match) abort
    let out = printf("%s|%s col %s| %s",
                \ a:match.filename,
                \ a:match.lnum,
                \ a:match.col,
                \ a:match.text)
    return [out]
endf

" ctrlsf#view#Indent()
"
func! ctrlsf#view#Indent() abort
    let maxlnum = ctrlsf#db#MaxLnum()
    return strlen(string(maxlnum)) + 1 + g:ctrlsf_indent
endf

" Reset()
"
" Reset all states of this module.
"
func! ctrlsf#view#Reset() abort
    let s:rendered_par = 0
    let s:rendered_match = 0
    let s:cur_file = ''
    let s:procbar_idx = 0
endf

" Render()
"
" Return rendered view of current resultset.
"
" Returns:
" Text of rendered view
"
func! ctrlsf#view#Render() abort
    call ctrlsf#view#Reset()
    if ctrlsf#CurrentMode() ==# 'normal'
        return s:NormalView()
    else
        return s:CompactView()
    endif
endf

" RenderIncr()
"
" Render incrementally.
"
" Returns:
" Text of rendered view to append
"
func! ctrlsf#view#RenderIncr(base_vlnum) abort
    if ctrlsf#CurrentMode() ==# 'normal'
        return s:NormalViewIncr(a:base_vlnum)
    else
        return s:CompactViewIncr(a:base_vlnum)
    endif
endf

" RenderSummaryState()
"
" Render the state summary.
"
func! ctrlsf#view#RenderSummaryState() abort
    if g:ctrlsf_search_mode ==# 'sync'
        return s:SummaryState(0)
    else
        if ctrlsf#async#IsSearching()
            let s:procbar_idx = (s:procbar_idx % len(s:procbar_spinner)) + 1
            return s:SummaryState(s:procbar_idx)
        elseif ctrlsf#async#IsCancelled()
            return s:SummaryState(-1)
        else
            return s:SummaryState(100)
        endif
    endif
endf

" RenderSummaryMatch()
"
" Render the match summary.
"
func! ctrlsf#view#RenderSummaryMatch() abort
    return s:SummaryMatch()
endf

" s:NormalViewIncr()
"
func! s:NormalViewIncr(base_vlnum) abort
    let resultset = ctrlsf#db#ResultSet()
    let to_render = resultset[s:rendered_par:-1]

    let view = [[],[]]
    let ind  = ctrlsf#view#Indent()

    for par in to_render
        if s:cur_file !=# par.filename
            let s:cur_file = par.filename
            if a:base_vlnum > 0
                call extend(view[0], [['~', 'ctrlsf_line_tilde']])
                call extend(view[1], [''])
                call extend(view[0], [['~', 'ctrlsf_line_tilde']])
                call extend(view[1], [''])
            endif
            call extend(view[0], [[repeat(' ', ind - 2) . '- ', 'ctrlsf_line_filename']])
            call extend(view[1], [s:Filename(par)])
        elseif !ctrlsf#opt#IsContextZero()
            call extend(view[0], [[repeat(' ', ind - 2) . '⋮ ', 'ctrlsf_line_separator']])
            call extend(view[1], [''])
        endif

        for line in par.lines
            let l = s:Line(line)
            call extend(view[0], [[l[0], 'ctrlsf_line' . (line.matched() ? '_match' : '_context')]])
            call extend(view[1], [l[1]])

            call line.set_vlnum(a:base_vlnum + len(view[1]))

            if line.matched()
                call line.match.set_vpos(line.vlnum(), line.match.col + ctrlsf#view#Indent())
            endif
        endfo
    endfo

    let s:rendered_par += len(to_render)

    return view
endf

" s:CompactViewIncr()
"
func! s:CompactViewIncr(base_vlnum) abort
    let matchlist = ctrlsf#db#MatchList()
    let to_render = matchlist[s:rendered_match:-1]

    let view = []

    for mat in to_render
        call extend(view, s:LineCompact(mat))

        let vlnum = a:base_vlnum + len(view)
        let indent = printf("%s|%s col %s| ",
                    \ mat.filename,
                    \ mat.lnum,
                    \ mat.col)
        let vcol = mat.col + len(indent)
        call mat.set_vpos(vlnum, vcol, 'compact')
    endfo

    let s:rendered_match = s:rendered_match + len(to_render)

    return view
endf

" s:NormalView()
"
func! s:NormalView() abort
    let body = 'NOT IMPLEMENTED'
    " join(s:NormalViewIncr(0), "\n")
    return body
endf

" s:CompactView()
"
func! s:CompactView() abort
    return join(s:CompactViewIncr(0), "\n")
endf

" Locate()
"
" Find resultset which is corresponding the given line.
"
" Parameters:
" {vlnum} number of a line within rendered view
"
" Returns:
" [file, line, match] if corresponding line contains one or more matches
" [file, line, {}]    if corresponding line doesn't contains any match
" ['', {}, {}]        if no corresponding line is found
"
func! ctrlsf#view#Locate(vlnum) abort
    if ctrlsf#CurrentMode() ==# 'normal'
        return s:LocateNormalView(a:vlnum)
    else
        return s:LocateCompactView(a:vlnum)
    endif
endf

" s:LocateCompactView()
"
func! s:LocateCompactView(vlnum) abort
    let matchlist = ctrlsf#db#MatchList()
    let match = get(matchlist, a:vlnum-1, {})
    if !empty(match)
        let line = ctrlsf#class#line#New(match.filename, match.lnum, match.text)
        return [match.filename, line, match]
    else
        return ['', {}, {}]
    endif
endf

" s:LocateNormalView()
"
func! s:LocateNormalView(vlnum) abort
    let resultset = ctrlsf#db#ResultSet()
    return s:BSearch(resultset, 0, len(resultset) - 1, a:vlnum)
endf

func! s:BSearch(resultset, left, right, vlnum) abort
    " case: not found
    if a:left > a:right
        return ['', {}, {}]
    endif

    let pivot = (a:left + a:right) / 2
    let par = a:resultset[pivot]

    " case: less than pivot
    if a:vlnum < par.vlnum()
        return s:BSearch(a:resultset, a:left, pivot - 1, a:vlnum)
    endif

    " case: greater than pivot
    if a:vlnum > par.vlnum() + par.range() - 1
        return s:BSearch(a:resultset, pivot + 1, a:right, a:vlnum)
    endif

    " case: found
    let ret = ['', {}, {}]

    " fetch file
    let ret[0] = par.filename

    " fetch line object
    let line = par.lines[a:vlnum - par.vlnum()]
    let ret[1] = line

    " fetch match object
    if line.matched()
        let ret[2] = line.match
    endif

    return ret
endf

" FindNextMatch()
"
" Find next match.
"
" Parameters:
" {forward} true or false
" {wrapscan} true or false
"
" Returns:
" [vlnum, vcol] line number and column number of next match
"
func! ctrlsf#view#FindNextMatch(forward, wrapscan, ...) abort
    let file_based = get(a:, 1, 0)

    if file_based
        let vlnum = s:FindNextFile(a:forward)
        call cursor(vlnum, 1)
    endif

    let regex = ctrlsf#pat#MatchPerLineRegex(ctrlsf#CurrentMode())
    let flag  = (a:forward || file_based) ? 'n' : 'nb'
    let flag .= a:wrapscan ? 'w' : 'W'
    return searchpos(regex, flag)
endf

func! s:FindNextFile(forward) abort
    let vmode = ctrlsf#CurrentMode()
    let fileset = ctrlsf#db#FileResultSet()

    if empty(fileset)
        return 0
    endif

    let cur_vlnum = line('.')

    let left = 0
    let right = len(fileset) - 1

    while left <= right
        let pivot = (left + right) / 2
        let file = fileset[pivot]

        if file.start_vlnum(vmode) > cur_vlnum
            let right = pivot - 1
        elseif file.end_vlnum(vmode) < cur_vlnum
            let left = pivot + 1
        else
            let current = pivot
            break
        endif
    endwh

    if !exists('current')
        let next = a:forward ? 0 : -1
    else
        let next = a:forward ?
                    \ (current + 1) % len(fileset) :
                    \ current - 1
    endif
    return fileset[next].first_match().vlnum(vmode)
endf

" Unrender()
"
" Return a 'ResultSet' which is unrendered from {content}.
"
func! ctrlsf#view#Unrender(content) abort
    let lines  = type(a:content) == 3 ? a:content : split(a:content, "\n")
    let orig   = ctrlsf#db#ResultSet()
    let indent = ctrlsf#view#Indent()

    let resultset = []

    let current_file = ''
    let next_file    = ''
    let offset       = 0
    let base_lnum    = -1

    let i = 0
    while i < len(lines)
        let buffer = []

        if len(resultset) >= len(orig)
            throw 'BrokenBufferException'
        endif
        let orig_para = orig[len(resultset)]
        let base_lnum = orig_para.lnum()

        while i < len(lines)
            let line = lines[i]
            let i += 1

            if line ==# '....' || line ==# ''
                break
            elseif line !~ '\v^\d+[:-]\s{2,}'
                " strip trailing colon
                let next_file = substitute(line, ':$', '', '')
                break
            else
                let lnum = base_lnum + len(buffer) + offset
                let content = strpart(line, indent)
                call add(buffer, [current_file, lnum, content])
                if ctrlsf#opt#IsContextZero()
                    break
                endif
            endif
        endwh

        if len(buffer) > 0
            let paragraph = ctrlsf#class#paragraph#New(buffer)

            " if derender failed, throw an exception
            if empty(paragraph.filename) || empty(paragraph.lines)
                throw 'BrokenBufferException'
            endif

            let offset += paragraph.range() - orig_para.range()

            call add(resultset, paragraph)
        endif

        " file boundary
        if next_file !=# current_file
            let offset = 0
            let current_file = next_file
        endif
    endwh

    return resultset
endf
