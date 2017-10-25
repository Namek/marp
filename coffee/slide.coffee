clsMarkdown = require './classes/mds_markdown'
ipc         = require('electron').ipcRenderer
Path        = require 'path'

resolvePathFromMarp = (path = './') -> Path.resolve(__dirname, '../', path)

document.addEventListener 'DOMContentLoaded', ->
  $ = window.jQuery = window.$ = require('jquery')

  do ($) ->
    # First, resolve Marp resources path
    $("[data-marp-path-resolver]").each ->
      for target in $(@).attr('data-marp-path-resolver').split(/\s+/)
        $(@).attr(target, resolvePathFromMarp($(@).attr(target)))

    Markdown = new clsMarkdown({ afterRender: clsMarkdown.generateAfterRender($) })

    themes = {}
    themes.current = -> $('#theme-css').attr('href')
    themes.default = themes.current()
    themes.apply = (path = null) ->
      toApply = resolvePathFromMarp(path || themes.default)

      if toApply isnt themes.current()
        $('#theme-css').attr('href', toApply)
        setTimeout applyScreenSize, 20

        return toApply.match(/([^\/]+)\.css$/)[1]
      false

    setStyle = (identifier, css) ->
      id  = "mds-#{identifier}Style"
      elm = $("##{id}")
      elm = $("<style id=\"#{id}\"></style>").appendTo(document.head) if elm.length <= 0
      elm.text(css)

    getCSSvar = (prop) -> document.defaultView.getComputedStyle(document.body).getPropertyValue(prop)

    getSlideSize = ->
      size =
        w: +getCSSvar '--slide-width'
        h: +getCSSvar '--slide-height'

      size.ratio = size.w / size.h
      size

    applySlideSize = (width, height) ->
      setStyle 'slideSize',
        """
        body {
          --slide-width: #{width || 'inherit'};
          --slide-height: #{height || 'inherit'};
        }
        """
      applyScreenSize()

    getScreenSize = ->
      size =
        w: document.documentElement.clientWidth
        h: document.documentElement.clientHeight

      previewMargin = +getCSSvar '--preview-margin'
      size.ratio = (size.w - previewMargin * 2) / (size.h - previewMargin * 2)
      size

    applyScreenSize = ->
      size = getScreenSize()
      setStyle 'screenSize', "body { --screen-width: #{size.w}; --screen-height: #{size.h}; }"
      $('#container').toggleClass 'height-base', size.ratio > getSlideSize().ratio

    applyCurrentPage = (page) ->
      @currentPage = page
      percentage = Math.min(100, Math.max(0, (page-1) / (@pageCount-1) * 100))
      setStyle 'currentPage',
        """
        @media not print {
          body.slide-view.screen .slide_wrapper:not(:nth-of-type(#{page})) {
            width: 0 !important;
            height: 0 !important;
            border: none !important;
            box-shadow: none !important;
          }
          body.slide-view.screen .slide_wrapper .slide_progress_bar {
            width: #{percentage}%;
          }
        }
        """

    applyStepFragmentInSlide = (currentPage, delta) ->
      newPage = currentPage
      allFragments = $("[id=\"#{currentPage}\"] .fragment").toArray().reverse()
      exposedFragments = allFragments.filter (el) -> el.classList.contains('fragment-exposed')
      leftFragmentsCount = allFragments.length - exposedFragments.length - delta

      # that's ugly, iknw
      isScreenMode = $('body.slide-view.screen').get().length > 0
      isPresentationMode = $('body.slide-view.presentation').get().length > 0

      if not isScreenMode and not isPresentationMode
        return

      shouldSwitchPage = not isPresentationMode or leftFragmentsCount < 0 or leftFragmentsCount > allFragments.length

      if shouldSwitchPage
        for el in allFragments
          (el.classList[if delta > 0 then 'add' else 'remove']) 'fragment-exposed'

        page = currentPage + delta
        if page > 0 and page <= @pageCount
          newPage = page
      else
        el.classList.remove 'fragment-exposed' for el in allFragments
        el.classList.add 'fragment-exposed' for el in allFragments[leftFragmentsCount..]

      if newPage != currentPage
        console.log(newPage)
        applyCurrentPage newPage
        ipc.sendToHost 'stepFragmentInSlide_reply', newPage

    render = (md) ->
      applySlideSize md.settings.getGlobal('width'), md.settings.getGlobal('height')
      md.changedTheme = themes.apply md.settings.getGlobal('theme')
      @pageCount = md.pageCount = md.rulers.length + 1

      $('#markdown').html(md.parsed)

      ipc.sendToHost 'rendered', md
      ipc.sendToHost 'rulerChanged', md.rulers if md.rulerChanged
      ipc.sendToHost 'themeChanged', md.changedTheme if md.changedTheme

    sendPdfOptions = (opts) ->
      slideSize = getSlideSize()

      opts.exportSize =
        width:  Math.floor(slideSize.w * 25400 / 96)
        height: Math.floor(slideSize.h * 25400 / 96)

      # Load slide resources
      $('body').addClass 'to-pdf'
      setTimeout (-> ipc.sendToHost 'responsePdfOptions', opts), 0

    setImageDirectory = (dir) -> $('head > base').attr('href', dir || './')

    ipc.on 'render', (e, md) -> render(Markdown.parse(md))
    ipc.on 'currentPage', (e, page) -> applyCurrentPage page
    ipc.on 'stepPresentation', (e, {currentPage, delta}) -> applyStepPresentation currentPage, delta
    ipc.on 'setClass', (e, classes) -> $('body').attr 'class', classes
    ipc.on 'setImageDirectory', (e, dir) -> setImageDirectory(dir)
    ipc.on 'requestPdfOptions', (e, opts) -> sendPdfOptions(opts || {})
    ipc.on 'unfreeze', -> $('body').removeClass('to-pdf')

    # Initialize
    $(document).on 'click', 'a', (e) ->
      e.preventDefault()
      ipc.sendToHost 'linkTo', $(e.currentTarget).attr('href')

    $(window).resize (e) -> applyScreenSize()
    applyScreenSize()

    window.addEventListener 'wheel', (e) ->
      console.log('wheel')
      if e.deltaY != 0
        applyStepFragmentInSlide(@currentPage, (if e.deltaY > 0 then 1 else -1))
