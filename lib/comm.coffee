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
    console.log "CONNECT"
    hasSocket = false
    hasSignal = false

    socket = Socket 'http://localhost:9448'
    signal = undefined

    socket.on 'connect', ->
      hasSocket = true
      console.log "SOCKET CONNECT"
      if hasSignal
        CommUtils.emitIdentity program, socket, signal

    socket.on 'client signal', (data) ->
      console.log "CLIENT SIGNAL", data
      peer.signal data

    peer = new Peer
      initiator: true
      wrtc: wrtc

    peer.on 'signal', (data) ->
      console.log "PEER SIGNAL", data
      if data.type isnt 'offer'
        # peer.signal data.candidate
        return

      hasSignal = true
      signal = data

      if hasSocket
        CommUtils.emitIdentity program, socket, signal

    peer.on 'data', (data) -> console.log "PEER DATA", data
    peer.on 'error', (err) -> console.log "PEER ERR", err
    peer.on 'connect', () ->
      peer.send JSON.stringify({awesome: true})
      console.log "PEER CONNECT"
      callback socket, peer

module.exports = CommUtils