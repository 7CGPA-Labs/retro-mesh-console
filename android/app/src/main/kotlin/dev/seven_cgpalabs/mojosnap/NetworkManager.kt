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

    // JNI Native Function in native-render.cpp
    external fun updatePlayer2Button(buttonId: Int, pressed: Boolean)

    fun startHost(context: Context) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        thread {
            try {
                serverSocket = ServerSocket(PORT)
                Log.d(TAG, "Server started on port $PORT")
                registerService()

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

    private fun registerService() {
        val serviceInfo = NsdServiceInfo().apply {
            serviceName = SERVICE_NAME
            serviceType = SERVICE_TYPE
            port = PORT
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

    fun startClient(context: Context) {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager
        
        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {
                Log.d(TAG, "Service discovery started")
            }
            override fun onServiceFound(service: NsdServiceInfo) {
                Log.d(TAG, "Service discovery success: $service")
                if (service.serviceType == SERVICE_TYPE && service.serviceName == SERVICE_NAME) {
                    nsdManager?.resolveService(service, object : NsdManager.ResolveListener {
                        override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {
                            Log.e(TAG, "Resolve failed: $errorCode")
                        }
                        override fun onServiceResolved(serviceInfo: NsdServiceInfo) {
                            Log.d(TAG, "Resolve Succeeded. ${serviceInfo.host}")
                            connectToServer(serviceInfo.host, serviceInfo.port)
                            nsdManager?.stopServiceDiscovery(discoveryListener)
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

    private fun connectToServer(host: InetAddress, port: Int) {
        thread {
            try {
                clientSocket = Socket(host, port)
                outputStream = clientSocket?.getOutputStream()
                Log.d(TAG, "Connected to server")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to connect", e)
            }
        }
    }

    fun sendInput(buttonId: Int, pressed: Boolean) {
        thread {
            try {
                val packet = ByteArray(2)
                packet[0] = if (pressed) 1 else 2
                packet[1] = buttonId.toByte()
                outputStream?.write(packet)
                outputStream?.flush()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send input", e)
            }
        }
    }

    fun stop() {
        try {
            registrationListener?.let { nsdManager?.unregisterService(it) }
            discoveryListener?.let { nsdManager?.stopServiceDiscovery(it) }
            serverSocket?.close()
            clientSocket?.close()
        } catch (e: Exception) {}
    }
}
