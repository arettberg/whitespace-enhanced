WhitespaceEnhanced = require './whitespace'

module.exports =
  activate: ->
    @whitespace_enhanced = new WhitespaceEnhanced()

  deactivate: ->
    @whitespace_enhanced?.destroy()
    @whitespace_enhanced = null
