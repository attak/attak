wrtc = require 'wrtc'
Peer = require 'simple-peer'
Socket = require 'socket.io-client'

CommUtils =
  emitIdentity: (program, socket, signal) ->
    identity =
      id: program.id
      type: 'attak cli'
      signal: signal

    socket.emit 'identity', identity

  connect: (program, callback) ->
    hasSocket = false
    hasSignal = false

    socket = Socket 'http://localhost:9448'
    signal = undefined

    socket.on 'connect', ->
      hasSocket = true
      if hasSignal
        CommUtils.emitIdentity program, socket, signal

    socket.on 'client signal', (data) ->
      peer.signal data

    peer = new Peer
      initiator: true
      wrtc: wrtc

    peer.on 'signal', (data) ->
      if data.type isnt 'offer' then return

      hasSignal = true
      signal = data

      if hasSocket
        CommUtils.emitIdentity program, socket, signal

    peer.on 'data', (data) -> console.log "PEER DATA", data
    peer.on 'error', (err) -> console.log "PEER ERR", err
    peer.on 'connect', () ->
      wrtcWrapper =
        emit: (type, data) ->
          peer.send JSON.stringify
            type: type
            data: data
      callback socket, wrtcWrapper

module.exports = CommUtils