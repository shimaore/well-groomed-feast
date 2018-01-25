    formats = ['mp3','wav']

    module.exports =
      find: (doc,base) ->
        return false unless doc?._attachments?

        format = formats.find (format) ->
          "#{base}.#{format}" of doc._attachments

        if format
          return "#{base}.#{format}"
        else
          return false

      name: (base) -> "#{base}.#{formats[0]}"
