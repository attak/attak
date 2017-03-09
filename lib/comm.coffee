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

    onSignal = (data) ->
      if data.type isnt 'offer' then return

      hasSignal = true
      signal = data

      if hasSocket
        CommUtils.emitIdentity program, socket, signal

    peer.on 'signal', onSignal
    peer.on 'data', (data) -> console.log "PEER DATA", data
    peer.on 'error', (err) -> console.log "PEER ERR", err

    wrtcWrapper =
      emit: (type, data) ->
        if peer.writable
          peer.send JSON.stringify
            type: type
            data: data

    peer.on 'connect', () ->
      callback socket, wrtcWrapper

    peer.on 'close', () =>
      console.log "PEER CLOSED"
      peer = new Peer
        initiator: true
        wrtc: wrtc

      peer.on 'signal', onSignal

module.exports = CommUtils