Package = require 'package'
fsUtils = require 'fs-utils'
path = require 'path'
_ = require 'underscore'
TextMateGrammar = require 'text-mate-grammar'
async = require 'async'

### Internal ###

module.exports =
class TextMatePackage extends Package
  @testName: (packageName) ->
    /(\.|_|-)tmbundle$/.test(packageName)

  @getLoadQueue: ->
    return @loadQueue if @loadQueue
    @loadQueue = async.queue (pack, done) ->
      pack.loadGrammars ->
        pack.loadScopedProperties(done)

    @loadQueue

  constructor: ->
    super
    @grammars = []
    @scopedProperties = []
    @metadata = {@name}

  load: ({sync}={}) ->
    if sync
      @loadGrammarsSync()
      @loadScopedPropertiesSync()
    else
      TextMatePackage.getLoadQueue().push(this)

  activate: ->
    syntax.addGrammar(grammar) for grammar in @grammars
    for { selector, properties } in @scopedProperties
      syntax.addProperties(@path, selector, properties)

  activateConfig: -> # noop

  deactivate: ->
    syntax.removeGrammar(grammar) for grammar in @grammars
    syntax.removeProperties(@path)

  legalGrammarExtensions: ['plist', 'tmLanguage', 'tmlanguage', 'json']

  loadGrammars: (done) ->
    fsUtils.isDirectoryAsync @getSyntaxesPath(), (isDirectory) =>
      if isDirectory
        fsUtils.listAsync @getSyntaxesPath(), @legalGrammarExtensions, (error, paths) =>
          if error?
            console.log("Error loading grammars of TextMate package '#{@path}':", error.stack, error)
            done()
          else
            async.eachSeries(paths, @loadGrammarAtPath, done)
      else
        done()

  loadGrammarAtPath: (grammarPath, done) =>
    TextMateGrammar.load grammarPath, (err, grammar) =>
      return console.log("Error loading grammar at path '#{grammarPath}':", err.stack ? err) if err
      @addGrammar(grammar)
      done()

  loadGrammarsSync: ->
    for grammarPath in fsUtils.list(@getSyntaxesPath(), @legalGrammarExtensions)
      @addGrammar(TextMateGrammar.loadSync(grammarPath))

  addGrammar: (grammar) ->
    @grammars.push(grammar)
    syntax.addGrammar(grammar) if @isActive()

  getGrammars: -> @grammars

  getSyntaxesPath: ->
    syntaxesPath = path.join(@path, "syntaxes")
    if fsUtils.isDirectory(syntaxesPath)
      syntaxesPath
    else
      path.join(@path, "Syntaxes")

  getPreferencesPath: ->
    preferencesPath = path.join(@path, "preferences")
    if fsUtils.isDirectory(preferencesPath)
      preferencesPath
    else
      path.join(@path, "Preferences")

  loadScopedPropertiesSync: ->
    for grammar in @getGrammars()
      if properties = @propertiesFromTextMateSettings(grammar)
        selector = syntax.cssSelectorFromScopeSelector(grammar.scopeName)
        @scopedProperties.push({selector, properties})

    for preferencePath in fsUtils.list(@getPreferencesPath())
      {scope, settings} = fsUtils.readObject(preferencePath)
      if properties = @propertiesFromTextMateSettings(settings)
        selector = syntax.cssSelectorFromScopeSelector(scope) if scope?
        @scopedProperties.push({selector, properties})

    for {selector, properties} in @scopedProperties
      syntax.addProperties(@path, selector, properties)

  loadScopedProperties: (callback) ->
    scopedProperties = []

    for grammar in @getGrammars()
      if properties = @propertiesFromTextMateSettings(grammar)
        selector = syntax.cssSelectorFromScopeSelector(grammar.scopeName)
        scopedProperties.push({selector, properties})

    preferenceObjects = []
    done = =>
      for {scope, settings} in preferenceObjects
        if properties = @propertiesFromTextMateSettings(settings)
          selector = syntax.cssSelectorFromScopeSelector(scope) if scope?
          scopedProperties.push({selector, properties})

      @scopedProperties = scopedProperties
      if @isActive()
        for {selector, properties} in @scopedProperties
          syntax.addProperties(@path, selector, properties)
      callback?()
    @loadTextMatePreferenceObjects(preferenceObjects, done)

  loadTextMatePreferenceObjects: (preferenceObjects, done) ->
    fsUtils.isDirectoryAsync @getPreferencesPath(), (isDirectory) =>
      return done() unless isDirectory

      fsUtils.listAsync @getPreferencesPath(), (error, paths) =>
        if error?
          console.log("Error loading preferences of TextMate package '#{@path}':", error.stack, error)
          done()
          return

        loadPreferencesAtPath = (preferencePath, done) ->
          fsUtils.readObjectAsync preferencePath, (error, preferences) =>
            if error?
              console.warn("Failed to parse preference at path '#{preferencePath}'", error.stack, error)
            else
              preferenceObjects.push(preferences)
            done()
        async.eachSeries paths, loadPreferencesAtPath, done

  propertiesFromTextMateSettings: (textMateSettings) ->
    if textMateSettings.shellVariables
      shellVariables = {}
      for {name, value} in textMateSettings.shellVariables
        shellVariables[name] = value
      textMateSettings.shellVariables = shellVariables

    editorProperties = _.compactObject(
      commentStart: _.valueForKeyPath(textMateSettings, 'shellVariables.TM_COMMENT_START')
      commentEnd: _.valueForKeyPath(textMateSettings, 'shellVariables.TM_COMMENT_END')
      increaseIndentPattern: textMateSettings.increaseIndentPattern
      decreaseIndentPattern: textMateSettings.decreaseIndentPattern
      foldEndPattern: textMateSettings.foldingStopMarker
    )
    { editor: editorProperties } if _.size(editorProperties) > 0
