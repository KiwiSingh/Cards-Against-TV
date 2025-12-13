package com.cardsagainsttv.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import kotlin.random.Random

private data class SnowParticle(
    var x: Float,
    var y: Float,
    val speed: Float,
    val size: Float
) {
    companion object {
        fun random(y: Float = Random.nextFloat()) = SnowParticle(
            x = Random.nextFloat(),
            y = y,
            speed = Random.nextFloat() * 0.002f + 0.001f,
            size = Random.nextFloat() * 3f + 2f
        )
    }
}

// Data class for ConfettiParticle to resolve 'Unresolved reference: Particle'
private data class ConfettiParticle(
    var x: Float,
    var y: Float,
    val size: Float,
    val speed: Float
)

@Composable
fun SnowOverlay(modifier: Modifier = Modifier) {
    val particles = remember { mutableStateListOf<SnowParticle>() }

    // Spawn initial particles
    LaunchedEffect(Unit) {
        repeat(120) {
            particles.add(SnowParticle.random())
        }
    }

    // ❄️ Animation loop
    LaunchedEffect(Unit) {
        while (true) {
            withFrameNanos { }

            particles.forEachIndexed { i, p ->
                p.y += p.speed
                if (p.y > 1f) {
                    particles[i] = SnowParticle.random(y = 0f)
                }
            }
        }
    }

    // Fixed: Imported fillMaxSize
    Canvas(modifier.fillMaxSize()) {
        particles.forEach { p ->
            drawCircle(
                color = Color.White,
                radius = p.size,
                center = Offset(
                    x = p.x * size.width,
                    y = p.y * size.height
                )
            )
        }
    }
}


@Composable
fun ConfettiOverlay(modifier: Modifier = Modifier, trigger: Boolean) {
    if (!trigger) return

    // Fixed: Defined ConfettiParticle and used it here
    val particles = remember {
        mutableStateListOf<ConfettiParticle>().apply {
             repeat(80) {
                 add(
                     ConfettiParticle(
                         x = Random.nextFloat(),
                         y = 0f,
                         size = Random.nextFloat() * 8f + 4f,
                         speed = Random.nextFloat() * 0.01f + 0.01f
                     )
                 )
             }
        }
    }
    
    // Animation loop for Confetti
    LaunchedEffect(Unit) {
         while (true) {
             withFrameNanos { }
             particles.forEach { 
                 it.y += it.speed 
             }
         }
    }

    Canvas(modifier) {
        particles.forEach {
            drawRect(
                color = listOf(
                    Color.Red, Color.Green, Color.Yellow,
                    Color.Cyan, Color.Magenta
                ).random(),
                topLeft = Offset(it.x * size.width, it.y * size.height),
                size = Size(it.size, it.size)
            )
        }
    }
}
