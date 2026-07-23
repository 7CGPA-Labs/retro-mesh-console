package dev.seven_cgpalabs.mojosnap

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread
import java.io.InputStream
import java.io.OutputStream

object NetworkManager {
    private const val TAG = "NetworkManager"
    private const val SERVICE_TYPE = "_retroconsole._tcp."
    private const val SERVICE_NAME = "MojoSnapConsoleHost"
    private const val PORT = 48293

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var discoveryListener: NsdManager.DiscoveryListener? = null

    private var serverSocket: ServerSocket? = null
    private var clientSocket: Socket? = null
    private var outputStream: OutputStream? = null

    var onHostsDiscovered: ((List<Map<String, Any>>) -> Unit)? = null
    var onHostDisconnected: (() -> Unit)? = null
    
    private val discoveredHostsList = mutableListOf<Map<String, Any>>()

    // JNI Native Function in native-render.cpp
    external fun updatePlayer2Button(buttonId: Int, pressed: Boolean)

    fun startHost(context: Context, coreName: String, playerName: String, pin: String) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        thread {
            try {
                serverSocket = ServerSocket(PORT)
                Log.d(TAG, "Server started on port $PORT")
                registerService(coreName, playerName, pin)

                while (!serverSocket!!.isClosed) {
                    val socket = serverSocket!!.accept()
                    Log.d(TAG, "Client connected!")
                    handleClient(socket)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Server error", e)
            }
        }
    }

    private fun handleClient(socket: Socket) {
        thread {
            try {
                val input: InputStream = socket.getInputStream()
                val buffer = ByteArray(2)
                while (true) {
                    val bytesRead = input.read(buffer)
                    if (bytesRead == -1) break
                    if (bytesRead == 2) {
                        val pressed = buffer[0].toInt() == 1
                        val buttonId = buffer[1].toInt()
                        updatePlayer2Button(buttonId, pressed)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Client disconnected", e)
            } finally {
                socket.close()
            }
        }
    }

    private fun registerService(coreName: String, playerName: String, pin: String) {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = "MojoSnap - $playerName"
            serviceType = SERVICE_TYPE
            port = PORT
            // Android API 21+ supports attributes
            setAttribute("core", coreName)
            setAttribute("pin", pin)
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                Log.d(TAG, "Service registered: ${info.serviceName}")
            }
            override fun onRegistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "Service registration failed: $errorCode")
            }
            override fun onServiceUnregistered(arg0: NsdServiceInfo) {}
            override fun onUnregistrationFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
        }
        nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
    }

    @Suppress("DEPRECATION")
    fun startDiscovery(context: Context) {
        discoveredHostsList.clear()
        onHostsDiscovered?.invoke(discoveredHostsList)
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}
            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType == SERVICE_TYPE && service.serviceName.contains("MojoSnap -")) {
                    nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}
                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            val ip = serviceInfo.host.hostAddress
                            var core = "nes" // default
                            var pin = ""
                            // Extract TXT record
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.LOLLIPOP) {
                                val coreBytes = serviceInfo.attributes["core"]
                                if (coreBytes != null) {
                                    core = String(coreBytes)
                                }
                                val pinBytes = serviceInfo.attributes["pin"]
                                if (pinBytes != null) {
                                    pin = String(pinBytes)
                                }
                            }
                            val hostMap = mapOf<String, Any>(
                                "ip" to (ip ?: ""),
                                "name" to serviceInfo.serviceName,
                                "core" to core,
                                "pin" to pin
                            )
                            discoveredHostsList.add(hostMap)
                            onHostsDiscovered?.invoke(discoveredHostsList)
                        }
                    })
                }
            }
            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }
        nsdManager?.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
    }

    fun stopDiscovery() {
        try {
            discoveryListener?.let { nsdManager?.stopServiceDiscovery(it) }
            discoveryListener = null
        } catch (e: Exception) {}
    }

    fun connectToServer(ip: String, port: Int) {
        thread {
            try {
                clientSocket = Socket(ip, port)
                outputStream = clientSocket?.getOutputStream()
                Log.d(TAG, "Connected to server")
                
                // Monitor disconnection
                val input = clientSocket?.getInputStream()
                val buffer = ByteArray(1)
                while (true) {
                    val read = input?.read(buffer)
                    if (read == -1 || read == null) {
                        Log.d(TAG, "Disconnected from server")
                        onHostDisconnected?.invoke()
                        break
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to connect", e)
                onHostDisconnected?.invoke()
            }
        }
    }

    private val sendExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private val packetBuffer = ByteArray(2)

    fun sendInput(buttonId: Int, pressed: Boolean) {
        sendExecutor.execute {
            try {
                synchronized(packetBuffer) {
                    packetBuffer[0] = if (pressed) 1 else 2
                    packetBuffer[1] = buttonId.toByte()
                    outputStream?.write(packetBuffer)
                    outputStream?.flush()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send input", e)
            }
        }
    }

    fun stop() {
        try {
            stopDiscovery()
            registrationListener?.let { nsdManager?.unregisterService(it) }
            registrationListener = null
            serverSocket?.close()
            clientSocket?.close()
        } catch (e: Exception) {}
    }
}
