Gaia    = require("lin").Gaia
util    = require("util")
spawn   = require("child_process").spawn
Massage = require("massagist").Massage
_       = require("massagist")._
cliff   = require("cliff")
degrees = require("lin").degrees
# FFI   = require("node-ffi/lib/ffi")


class Ephemeris

  # @settings.out can be:
  # "tab" (should become eden's default), uses Your CLI Formatting Friend
  # "json" (is python's default)
  # "print" (python's print)
  # "pprint" (python's pretty-substitutes swe labels)
  # "inspect" (even prettier)
  # ... see Massage for more

  defaults:
    "root": "#{__dirname}/../"
    "data": "node_modules/precious/node_modules/gravity/data/"
    "out": "json"
    "time": null
    "geo": {"lat": null, "lon": null}
    "dms": false
    "stuff": [ [0, 3], [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 15, 17, 18, 19, 20], [136199, 7066, 50000, 90377, 20000] ]
    "houses": "K"

  bindings:
    "swe_set_ephe_path": ["void", ["string"]]
    "swe_get_planet_name": ["string", ["int32"]]
    "swe_utc_to_jd": ["int32", ["int32", "int32", "int32", "int32", "int32", "double", "int32", "double", "string", "pointer", "string"]]
    "swe_close": ["void", []]

  constructor: (@specifics = {}) ->
    @settings = _.allFurther(@defaults, @specifics)
    # @ffi = new FFI.Library __dirname + "/../lib/swe", @bindings

    unless @settings.data.match /^\//
      # if not absolute then relative (to eden) ephemeris data path
      @settings.data = "#{@settings.root}#{@settings.data}"

    @gaia = new Gaia @settings["geo"], @settings["time"]
    @settings.geo = {} # NOTE: overwrites the original geo - it should be an equivalent...
    @settings.geo.lat = @gaia.lat
    @settings.geo.lon = @gaia.lon
    @settings.ut = @gaia.ut

  # not used
  # ffi hard to install (npm issue)
  # ephemeris provided by precious module
  swe: (call) ->
    f = "swe_#{call}"
    # console.log arguments
    # @ffi[f].call this, (0) # it works with "Bus Error" (or seemed to work)
    # if the rest of arguments were args... (splat = Array), we could call:
    # @ffi[f].apply this, args # but it doesn't work ("Segmentation fault")
    # with(this) { eval "@ffi[f] 1;" } # SyntaxError: Reserved word "with"
    switch arguments.length
      when  0 then throw new Error "what do we call?"
      when  1 then @ffi[f]()
      when  2 then @ffi[f] arguments[1]
      when  3 then @ffi[f] arguments[1], arguments[2]
      when  4 then @ffi[f] arguments[1], arguments[2], arguments[3]
      when  5 then @ffi[f] arguments[1], arguments[2], arguments[3], arguments[4]
      when  6 then @ffi[f] arguments[1], arguments[2], arguments[3], arguments[4], arguments[5]
      when  7 then @ffi[f] arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6]
      when  8 then @ffi[f] arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7]
      when  9 then @ffi[f] arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8]
      when 10 then @ffi[f] arguments[1], arguments[2], arguments[3], arguments[4], arguments[5], arguments[6], arguments[7], arguments[8], arguments[9]
      else throw new Error "too many arguments..."

  run: (stream, treats) ->
    ephemeris = spawn "python", ["ephemeris.py", "#{JSON.stringify(@settings)}"]
                              , { cwd: __dirname + "/../node_modules/precious/lib" }
    treats = @settings.out if @settings.out instanceof Array and not treats?
    if treats?
      massage = new Massage treats
      massage.pipe ephemeris.stdout, stream, "ascii"
    else if @settings.out is "phase"
      # this is a bit ugly because it's easier to not change the precious output
      # will need to at least add an input method to lin's itemerge (soon)
      ensemble = new (require "lin").Ensemble
      ephemeris.stdout.on "data", (data) ->
        rpad = ' ' # pad on the right of each column (the values)
        labels =
          "0": "   longitude"
          "3": " speed"
        json = JSON.parse data
        idx = 0
        [objs, rows, colors] = [[], [" ", "what"], []]
        for i, group of json
          if i is "1" or i is "2"
            for id, it of group
              sid = if i is "2" then "#{10000 + new Number(id)}" else id
              item = ensemble.sid sid
              [lead, what] = [(if i is "2" then "+" else ""), id]
              if item.get('id') isnt '?'
                lead = item.get('u').white if item.get('u')?
                what = item.get('name')
              objs.push
                " ": lead + rpad
                "what": what + rpad
              for key, val of it
                label = labels[key] ? key
                switch key
                  when "0"
                    objs[idx][label] = degrees.lon(val).rep('str') + rpad
                  when "3"
                    rows.push '~' if idx is 0
                    objs[idx]['~'] = if val < 0 then '℞'.red else ''
                    # precision, rounding and alignment (if negative not <= -10?)
                    val = val.toFixed 3
                    val = (if val < 0 or val >=10  then val else " " + val)
                    objs[idx][label] = val + rpad
                  else objs[idx][label] = val + rpad
                rows.push labels[key] if idx is 0
              idx++
        objs = _.sortBy objs, (obj) -> obj[labels['0']] # longitude-sorted
        colors.push "white" for row in rows
        stream.write cliff.stringifyObjectRows objs, rows, colors
        stream.write "\n\n"
    else if _.include ["inspect", "indent"], @settings.out
      massage = new Massage ["json", @settings.out]
      massage.pipe ephemeris.stdout, stream, "ascii"
    else
      ephemeris.stdout.pipe stream

    ephemeris.stderr.on "data", (data) ->
      console.log data.toString("ascii")
    ephemeris.on "exit", (code) ->
      if code isnt 0
        console.log 'ephemeris exited with code ' + code;


module.exports = Ephemeris
