package dev.seven_cgpalabs.mojosnap

import org.junit.Test
import org.junit.Assert.*
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

class NetworkManagerTest {

    @Test
    fun testNetworkManagerSendInput() {
        val latch = CountDownLatch(1)
        var receivedButtonId = -1
        var receivedPressed = false

        // Start a dummy server to test client connection and sendInput
        thread {
            val serverSocket = ServerSocket(48293)
            val socket = serverSocket.accept()
            val input = socket.getInputStream()
            val buffer = ByteArray(2)
            val bytesRead = input.read(buffer)
            if (bytesRead == 2) {
                receivedPressed = buffer[0].toInt() == 1
                receivedButtonId = buffer[1].toInt()
            }
            latch.countDown()
            socket.close()
            serverSocket.close()
        }

        // Wait a bit for server to start
        Thread.sleep(500)

        NetworkManager.connectToServer("127.0.0.1", 48293)
        Thread.sleep(500)

        // Test sending input
        NetworkManager.sendInput(5, true) // A button pressed

        val received = latch.await(2, TimeUnit.SECONDS)
        
        assertTrue("Server should have received data", received)
        assertEquals("Button ID should match", 5, receivedButtonId)
        assertTrue("Pressed state should match", receivedPressed)
        
        NetworkManager.stop()
    }
}
