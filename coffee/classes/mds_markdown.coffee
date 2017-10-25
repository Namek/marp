highlightJs  = require 'highlight.js'
twemoji      = require 'twemoji'
extend       = require 'extend'
markdownIt   = require 'markdown-it'
Path         = require 'path'
MdsMdSetting = require './mds_md_setting'
{exist}      = require './mds_file'

wasCalled = false

setupCustomPlugin = (md) =>
  marker_str_beg = '/-'
  marker_str_end = '-/'

  marker_regex = /\/-[^-]-\//mg

  render = (tokens, idx, _options, env, self) ->
    # {content} = tokens[idx]
    # return if content.substring(0, 2) != '/-'

    # if matched = marker_regex.exec(content)
    #   console.log(matched)
    #   debugger
      


    # add a class to the opening tag
    if tokens[idx].nesting == 1
      tokens[idx].attrPush([ 'class', name ])

    self.renderToken(tokens, idx, _options, env, self)
  

  container = (state, startLine, endLine, silent) ->
    return false
    start = state.bMarks[startLine] + state.tShift[startLine]
    max = state.eMarks[startLine]
    line = state.src.substring(start, max)

    i = start

    found = false

    isOneLiner = false
    if state.src[start] == '/' and state.src[start+1] != '-'
      isOneLiner = true
      end = max
      maxLine = startLine
      found = true
    else
      # search for opening tag '/-'
      while i < max
        if state.src[i] == '/' and state.src[i+1] == '-'
          found = true
          break
        i += 1

      if not found
        return false

      start = i+2

      # search for closing tag '-/'
      while i < state.src.length-1
        if state.src[i] == '-' and state.src[i+1] == '/'
          i++
          break
        i++

      c1 = state.src[i-1]
      c2 = state.src[i]
      found = state.src[i-1] == '-' and state.src[i] == '/'
    

    if not found
      return false
    else
      end = i - 1
      console.log(start, end)
      text = state.src.substring(start, end)
      console.log(text)

    old_parent = state.parentType
    old_line_max = state.lineMax
    state.parentType = 'container'

    # this will prevent lazy continuations from ever going past our end marker
    state.lineMax = nextLine

    token        = state.push('fragment_open', 'span', 1)
    token.markup = markup
    token.block  = true
    token.info   = params
    token.map    = [ startLine, nextLine ]

    state.md.block.tokenize(state, startLine + 1, nextLine)

    token        = state.push('fragment_close', 'span', -1)
    token.markup = state.src.slice(start, pos)
    token.block  = true

    state.parentType = old_parent
    state.lineMax = old_line_max
    state.line = nextLine + (auto_closed ? 1 : 0)

    true



  md.block.ruler.before('fence', 'fragment', container, {
    alt: [ 'paragraph', 'reference', 'blockquote', 'list' ]
  })

  md.renderer.rules.fragment_open = render
  md.renderer.rules.fragment_close = render

module.exports = class MdsMarkdown
  @slideTagOpen:  (page) -> '<div class="slide_wrapper" id="' + page + '"><div class="slide"><div class="slide_bg"></div><div class="slide_inner">'
  @slideTagClose: (page) -> '</div><footer class="slide_footer"></footer>' +
    '<div class="slide_progress_bar"></div>' +
    '<span class="slide_page" data-page="' + page + '">' + page + '</span></div></div>'

  @highlighter: (code, lang) ->
    if lang?
      if lang == 'text' or lang == 'plain'
        return ''
      else if highlightJs.getLanguage(lang)
        try
          return highlightJs.highlight(lang, code, true).value

    highlightJs.highlightAuto(code).value

  @default:
    options:
      html: true
      xhtmlOut: true
      breaks: true
      linkify: true
      highlight: @highlighter

    plugins:
      'markdown-it-mark': {}
      'markdown-it-emoji':
        shortcuts: {}
      'markdown-it-katex': {}
      'markdown-it-classy': {}
      'markdown-it-container': "fragment"
      # 'markdown-it-decorate': {}

    twemoji:
      base: Path.resolve(__dirname, '../../node_modules/twemoji/2') + Path.sep
      size: 'svg'
      ext: '.svg'

  @createMarkdownIt: (opts, plugins) ->
    md = markdownIt(opts)
    md.use(require(plugName), plugOpts ? {}) for plugName, plugOpts of plugins
    setupCustomPlugin(md)
    md

  @generateAfterRender: ($) ->
    (md) ->
      mdElm = $("<div>#{md.parsed}</div>")

      mdElm.find('p > img[alt~="bg"]').each ->
        $t  = $(@)
        p   = $t.parent()
        bg  = $t.parents('.slide_wrapper').find('.slide_bg')
        src = $t[0].src
        alt = $t.attr('alt')
        elm = $('<div class="slide_bg_img"></div>').css('backgroundImage', "url(#{src})").attr('data-alt', alt)

        for opt in alt.split(/\s+/)
          elm.css('backgroundSize', "#{m[1]}%") if m = opt.match(/^(\d+(?:\.\d+)?)%$/)

        elm.appendTo(bg)
        $t.remove()
        p.remove() if p.children(':not(br)').length == 0 && /^\s*$/.test(p.text())

      mdElm.find('img[alt*="%"]').each ->
        for opt in $(@).attr('alt').split(/\s+/)
          if m = opt.match(/^(\d+(?:\.\d+)?)%$/)
            $(@).css('zoom', parseFloat(m[1]) / 100.0)

      mdElm
        .children('.slide_wrapper')
        .each ->
          $t = $(@)

          # Page directives for themes
          page = $t[0].id
          for prop, val of md.settings.getAt(+page, false)
            $t.attr("data-#{prop}", val)
            $t.find('footer.slide_footer:last').text(val) if prop == 'footer'

          # Detect "only-***" elements
          inner = $t.find('.slide > .slide_inner')
          innerContents = inner.children().filter(':not(base, link, meta, noscript, script, style, template, title)')

          headsLength = inner.children(':header').length
          $t.addClass('only-headings') if headsLength > 0 && innerContents.length == headsLength

          quotesLength = inner.children('blockquote').length
          $t.addClass('only-blockquotes') if quotesLength > 0 && innerContents.length == quotesLength

      md.parsed = mdElm.html()

  rulers: []
  settings: new MdsMdSetting
  afterRender: null
  twemojiOpts: {}

  constructor: (settings) ->
    opts         = extend({}, MdsMarkdown.default.options, settings?.options || {})
    plugins      = extend({}, MdsMarkdown.default.plugins, settings?.plugins || {})
    @twemojiOpts = extend({}, MdsMarkdown.default.twemoji, settings?.twemoji || {})
    @afterRender = settings?.afterRender || null
    @markdown    = MdsMarkdown.createMarkdownIt.call(@, opts, plugins)
    @afterCreate()

  afterCreate: =>
    md      = @markdown
    {rules} = md.renderer

    defaultRenderers =
      image:      rules.image
      html_block: rules.html_block

    extend rules,
      emoji: (token, idx) =>
        twemoji.parse(token[idx].content, @twemojiOpts)

      hr: (token, idx) =>
        ruler.push token[idx].map[0] if ruler = @_rulers
        "#{MdsMarkdown.slideTagClose(ruler.length || '')}#{MdsMarkdown.slideTagOpen(if ruler then ruler.length + 1 else '')}"

      image: (args...) =>
        @renderers.image.apply(@, args)
        defaultRenderers.image.apply(@, args)

      html_block: (args...) =>
        @renderers.html_block.apply(@, args)
        defaultRenderers.html_block.apply(@, args)

  parse: (markdown) =>
    # A lil' hacky way to provide "fragments" with `/` operator in the beginning of line.
    # Element on this line will have "fragment" styling class.
    markdown = markdown.replace(/^\/[^-](.+$)/mg, "$1 {fragment}")

    # Now let's provide the fragment blocks with `/-` and `-/`.
    #markdown = markdown.replace(/^\/-/mg, "::: fragment\n")
      # .replace(/-\//mg, "\n:::")

    @_rulers          = []
    @_settings        = new MdsMdSetting
    @settingsPosition = []
    @lastParsed       = """
                        #{MdsMarkdown.slideTagOpen(1)}
                        #{@markdown.render markdown}
                        #{MdsMarkdown.slideTagClose(@_rulers.length + 1)}
                        """
    ret =
      parsed: @lastParsed
      settingsPosition: @settingsPosition
      rulerChanged: @rulers.join(",") != @_rulers.join(",")

    @rulers   = ret.rulers   = @_rulers
    @settings = ret.settings = @_settings

    @afterRender(ret) if @afterRender?
    ret

  renderers:
    image: (tokens, idx, options, env, self) ->
      src = decodeURIComponent(tokens[idx].attrs[tokens[idx].attrIndex('src')][1])
      tokens[idx].attrs[tokens[idx].attrIndex('src')][1] = src if exist(src)

    html_block: (tokens, idx, options, env, self) ->
      {content} = tokens[idx]
      return if content.substring(0, 3) isnt '<!-'

      if matched = /^(<!-{2,}\s*)([\s\S]*?)\s*-{2,}>$/m.exec(content)
        spaceLines = matched[1].split("\n")
        lineIndex  = tokens[idx].map[0] + spaceLines.length - 1
        startFrom  = spaceLines[spaceLines.length - 1].length

        for mathcedLine in matched[2].split("\n")
          parsed = /^(\s*)(([\$\*]?)(\w+)\s*:\s*(.*))\s*$/.exec(mathcedLine)

          if parsed
            startFrom += parsed[1].length
            pageIdx = @_rulers.length || 0

            if parsed[3] is '$'
              @_settings.setGlobal parsed[4], parsed[5]
            else
              @_settings.set pageIdx + 1, parsed[4], parsed[5], parsed[3] is '*'

            @settingsPosition.push
              pageIdx: pageIdx
              lineIdx: lineIndex
              from: startFrom
              length: parsed[2].length
              property: "#{parsed[3]}#{parsed[4]}"
              value: parsed[5]

          lineIndex++
          startFrom = 0
