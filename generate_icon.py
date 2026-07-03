from svg_turtle import SvgTurtle
from svglib.svglib import svg2rlg
from reportlab.graphics import renderPM
import random
import os

def draw_star(t, x, y, size):
    t.penup()
    t.goto(x, y)
    t.pendown()
    t.color("white")
    t.begin_fill()
    for _ in range(5):
        t.forward(size)
        t.right(144)
    t.end_fill()

def draw_firework(t, x, y, color):
    t.penup()
    t.goto(x, y)
    t.pendown()
    t.color(color)
    t.pensize(3)
    for _ in range(12):
        t.forward(50)
        t.backward(50)
        t.right(30)

def draw_nes_controller(t):
    # Controller Body
    t.penup()
    t.goto(-150, -50)
    t.setheading(0)
    t.pendown()
    t.color("#2A2A2A", "#E0E0E0") # Light grey body
    t.pensize(5)
    t.begin_fill()
    for _ in range(2):
        t.forward(300)
        t.circle(10, 90)
        t.forward(100)
        t.circle(10, 90)
    t.end_fill()
    
    # Black inner rectangle
    t.penup()
    t.goto(-130, -30)
    t.pendown()
    t.color("black", "#1A1A1A")
    t.begin_fill()
    for _ in range(2):
        t.forward(260)
        t.left(90)
        t.forward(60)
        t.left(90)
    t.end_fill()

    # D-Pad
    t.penup()
    t.goto(-100, -10)
    t.pendown()
    t.color("black", "black")
    t.begin_fill()
    # Cross shape
    t.setheading(90)
    for _ in range(4):
        t.forward(20)
        t.right(90)
        t.forward(20)
        t.left(90)
        t.forward(20)
        t.right(90)
    t.end_fill()
    
    # Select / Start buttons
    t.penup()
    t.goto(-20, 0)
    t.setheading(0)
    t.pendown()
    t.color("black", "black")
    t.begin_fill()
    t.forward(30)
    t.left(90)
    t.forward(10)
    t.left(90)
    t.forward(30)
    t.left(90)
    t.forward(10)
    t.end_fill()
    
    t.penup()
    t.goto(20, 0)
    t.setheading(0)
    t.pendown()
    t.color("black", "black")
    t.begin_fill()
    t.forward(30)
    t.left(90)
    t.forward(10)
    t.left(90)
    t.forward(30)
    t.left(90)
    t.forward(10)
    t.end_fill()
    
    # A / B Buttons (Red circles)
    t.penup()
    t.goto(80, 5)
    t.setheading(0)
    t.pendown()
    t.color("#CC0000", "#FF0000")
    t.begin_fill()
    t.circle(15)
    t.end_fill()

    t.penup()
    t.goto(120, 5)
    t.pendown()
    t.color("#CC0000", "#FF0000")
    t.begin_fill()
    t.circle(15)
    t.end_fill()

def main():
    width = 1024
    height = 1024
    t = SvgTurtle(width, height)
    t.speed(0)
    
    # Background - draw a large rectangle
    t.penup()
    t.goto(-width/2, -height/2)
    t.pendown()
    t.color("#0A0A2A", "#0A0A2A")
    t.begin_fill()
    for _ in range(4):
        t.forward(width)
        t.left(90)
    t.end_fill()
    
    # Stars
    for _ in range(50):
        x = random.randint(-400, 400)
        y = random.randint(-400, 400)
        draw_star(t, x, y, random.randint(3, 8))
        
    # Fireworks
    colors = ["#FF5733", "#FFC300", "#DAF7A6", "#33FF57", "#3357FF", "#FF33F6"]
    for _ in range(8):
        x = random.randint(-300, 300)
        y = random.randint(-100, 300)
        draw_firework(t, x, y, random.choice(colors))
        
    # NES Controller
    draw_nes_controller(t)
    
    if not os.path.exists("assets"):
        os.makedirs("assets")
        
    # Save SVG
    svg_path = "assets/icon.svg"
    t.save_as(svg_path)
    
    # Convert to PNG
    png_path = "assets/icon.png"
    drawing = svg2rlg(svg_path)
    renderPM.drawToFile(drawing, png_path, fmt="PNG")
    print("Saved to assets/icon.png")

if __name__ == "__main__":
    main()
