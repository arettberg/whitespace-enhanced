{CompositeDisposable} = require 'atom'
{repositoryForPath} = require './helpers'

module.exports =
class WhitespaceEnhanced
  constructor: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.workspace.observeTextEditors (editor) =>
      @handleEvents(editor)
      @subscribeToRepository(editor)

    @subscriptions.add atom.commands.add 'atom-workspace',
      'whitespace-enhanced:remove-trailing-whitespace': =>
        if editor = atom.workspace.getActiveTextEditor()
          @removeTrailingWhitespace(editor, editor.getGrammar().scopeName)
      'whitespace-enhanced:convert-tabs-to-spaces': =>
        if editor = atom.workspace.getActiveTextEditor()
          @convertTabsToSpaces(editor)
      'whitespace-enhanced:convert-spaces-to-tabs': =>
        if editor = atom.workspace.getActiveTextEditor()
          @convertSpacesToTabs(editor)

  destroy: ->
    @subscriptions.dispose()

  handleEvents: (editor) ->
    buffer = editor.getBuffer()
    bufferSavedSubscription = buffer.onWillSave =>
      buffer.transact =>
        scopeDescriptor = editor.getRootScopeDescriptor()
        if atom.config.get('whitespace-enhanced.removeTrailingWhitespace', scope: scopeDescriptor)
          @removeTrailingWhitespace(editor, editor.getGrammar().scopeName)
        if atom.config.get('whitespace-enhanced.ensureSingleTrailingNewline', scope: scopeDescriptor)
          @ensureSingleTrailingNewline(editor)

    editorTextInsertedSubscription = editor.onDidInsertText (event) =>
      scopeDescriptor = editor.getRootScopeDescriptor()
      @getModifiedLines(editor) if atom.config.get('whitespace-enhanced.ignoreUnmodifiedLines', scope: scopeDescriptor)

      return unless event.text is '\n'
      return unless buffer.isRowBlank(event.range.start.row)

      if atom.config.get('whitespace-enhanced.removeTrailingWhitespace', scope: scopeDescriptor)
        unless atom.config.get('whitespace-enhanced.ignoreWhitespaceOnlyLines', scope: scopeDescriptor)
          editor.setIndentationForBufferRow(event.range.start.row, 0)

    editorDestroyedSubscription = editor.onDidDestroy =>
      bufferSavedSubscription.dispose()
      editorTextInsertedSubscription.dispose()
      editorDestroyedSubscription.dispose()

      @subscriptions.remove(bufferSavedSubscription)
      @subscriptions.remove(editorTextInsertedSubscription)
      @subscriptions.remove(editorDestroyedSubscription)

    @subscriptions.add(bufferSavedSubscription)
    @subscriptions.add(editorTextInsertedSubscription)
    @subscriptions.add(editorDestroyedSubscription)

  removeTrailingWhitespace: (editor, grammarScopeName) ->
    buffer = editor.getBuffer()
    scopeDescriptor = editor.getRootScopeDescriptor()

    ignoreCurrentLine = atom.config.get('whitespace-enhanced.ignoreWhitespaceOnCurrentLine', scope: scopeDescriptor)
    ignoreWhitespaceOnlyLines = atom.config.get('whitespace-enhanced.ignoreWhitespaceOnlyLines', scope: scopeDescriptor)
    ignoreUnmodifiedLines = atom.config.get('whitespace-enhanced.ignoreUnmodifiedLines', scope: scopeDescriptor)

    buffer.backwardsScan /[ \t]+$/g, ({lineText, match, replace, range}) =>
      try
        return if ignoreUnmodifiedLines and (@modifiedLines instanceof Array) and !((range.start.row + 1) in @modifiedLines)

        whitespaceRow = buffer.positionForCharacterIndex(match.index).row
        cursorRows = (cursor.getBufferRow() for cursor in editor.getCursors())

        return if ignoreCurrentLine and whitespaceRow in cursorRows

        [whitespace] = match
        return if ignoreWhitespaceOnlyLines and whitespace is lineText

        if grammarScopeName is 'source.gfm' and atom.config.get('whitespace-enhanced.keepMarkdownLineBreakWhitespace')
          # GitHub Flavored Markdown permits two or more spaces at the end of a line
          replace('') unless whitespace.length >= 2 and whitespace isnt lineText
        else
          replace('')
      catch error
        console.error error

  ensureSingleTrailingNewline: (editor) ->
    buffer = editor.getBuffer()
    lastRow = buffer.getLastRow()

    if buffer.lineForRow(lastRow) is ''
      row = lastRow - 1
      buffer.deleteRow(row--) while row and buffer.lineForRow(row) is ''
    else
      selectedBufferRanges = editor.getSelectedBufferRanges()
      buffer.append('\n')
      editor.setSelectedBufferRanges(selectedBufferRanges)

  convertTabsToSpaces: (editor) ->
    buffer = editor.getBuffer()
    spacesText = new Array(editor.getTabLength() + 1).join(' ')

    buffer.transact ->
      buffer.scan /\t/g, ({replace}) -> replace(spacesText)

    editor.setSoftTabs(true)

  convertSpacesToTabs: (editor) ->
    buffer = editor.getBuffer()
    spacesText = new Array(editor.getTabLength() + 1).join(' ')

    buffer.transact ->
      buffer.scan new RegExp(spacesText, 'g'), ({replace}) -> replace('\t')

    editor.setSoftTabs(false)

  subscribeToRepository: (editor) ->
    @repository = repositoryForPath(editor.getPath())

  getModifiedLines: (editor) ->
    return if editor.isDestroyed()

    @modifiedLines = @modifiedLines || []

    if path = editor?.getPath()
      @repository?.getLineDiffs(path, editor.getText())
        .catch (e) =>
          if e.message.match(/does not exist in the given tree/)
            true
          else
            Promise.reject(e)
        .then (diffs) =>
          if diffs is true
            @modifiedLines = true
          else
            @modifiedLines = diffs.reduce (lines, diff) ->
              lineNumber = diff.newStart
              lines.push(lineNumber++) for i in [0...diff.newLines]
              return lines
            , []

        .catch (e) ->
          console.error('Error getting line diffs for ' + path + ':')
          console.error(e)
