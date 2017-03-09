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

    onSignal = (data) ->
      if data.type isnt 'offer' then return

      hasSignal = true
      signal = data

      if hasSocket
        CommUtils.emitIdentity program, socket, signal

    wrtcWrapper =
      emit: (type, data) ->
        if peer.writable
          peer.send JSON.stringify
            type: type
            data: data
      signal: (data) ->
        peer.signal data

    reconnectPeer = () ->
      peer = new Peer
        initiator: true
        wrtc: wrtc

      wrtcWrapper.signal = (data) ->
        if peer.destroyed
          reconnectPeer()
        peer.signal data

      wrtcWrapper.emit = (type, data) ->
        if peer.writable
          peer.send JSON.stringify
            type: type
            data: data

      peer.on 'signal', onSignal
      peer.on 'close', () => reconnectPeer()
      peer.on 'connect', () -> wrtcWrapper.reconnect wrtcWrapper

    peer = new Peer
      initiator: true
      wrtc: wrtc

    socket.on 'client signal', (data) ->
      wrtcWrapper.signal data

    peer.on 'signal', onSignal
    peer.on 'data', (data) -> console.log "PEER DATA", data
    peer.on 'error', (err) -> console.log "PEER ERR", err
    peer.on 'connect', () -> callback socket, wrtcWrapper
    peer.on 'close', () => reconnectPeer()

module.exports = CommUtils