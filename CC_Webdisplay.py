from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from xvfbwrapper import Xvfb # Only works on linux
from fastapi import FastAPI,Response
from mss import mss
from PIL import Image # USE PILLOW-SIMD FOR FASTER PERFORMANCE 
from threading import Event, Thread
from time import perf_counter
from os import getcwd
import uvicorn
PORT = 5001
IND_CC_WIDTH,IND_CC_HEIGHT = 0,0
TOT_CC_WIDTH,TOT_CC_HEIGHT = 0,0
# start the virtual display
vdisplay = Xvfb(width=1280,height=720)
vdisplay.start()
# import this right ater
import pyautogui
pyautogui.FAILSAFE = False

CC_COLORS = (
    (240, 240, 240), # white, 0
    (242, 178, 51),  # orange, 1
    (229, 127, 216), # magenta, 2
    (153, 178, 242), # lightBlue, 3
    (222, 222, 108), # yellow, 4
    (127, 204, 25),  # lime, 5
    (242, 178, 204), # pink, 6
    (76, 76, 76),    # gray, 7
    (153, 153, 153), # lightGray, 8
    (76, 153, 178),  # cyan, 9
    (178, 102, 229), # purple, a
    (51, 102, 204),  # blue, b
    (127, 102, 76),  # brown, c
    (87, 166, 78),   # green, d
    (204, 76, 76),   # red, e
    (17, 17, 17)     # black, f
)
# CC Color table generator
pal_im = Image.new("P", (1, 1))
def init(colors):
    color_vals = []
    for color in colors:
        for val in color:
            color_vals.append(val)
    color_vals = tuple(color_vals)
    pal_im.putpalette(color_vals + colors[-1] * (256 - len(colors)))
# Run this at startup
init(CC_COLORS)


class WebBrowser:
    def __init__(self):
        # load up web browser
        Thread(target=self.main).start()

    def main(self):
        self.lock = Event()
        self.dead = Event()
        self.screenshot = mss()
        # startup chrome
        chrome_options = Options()
        chrome_options.add_argument("--remote-debugging-port=9333")

        self.browser = webdriver.Chrome(executable_path=getcwd()+"/chrome-linux-x64/chromedriver",options=chrome_options)
        self.browser.maximize_window()
        self.browser.get("https://google.com/search?q=google")
        # stop here and wait
        self.lock.wait()
        # close the web browser
        self.browser.close()
        # set as dead
        self.dead.set()

    def takepicture(self):
        return self.screenshot.grab(self.screenshot.monitors[1])

    def exit(self):
        self.lock.set()
        self.dead.wait()

    def seturl(self,link):
        print("getting "+link)
        self.browser.get(link)

    def click(self,x,y):
        pyautogui.click(x,y)
        
    def keypress(self,x):
        pyautogui.press(x)

class Uvicorn_Server(uvicorn.Server):
    def run_uvi(self):
        self.thread = Thread(target=self.run)
        self.thread.start()
    def kill_uvi(self):
        self.should_exit = True
        self.thread.join()

Webbie = WebBrowser()
App = FastAPI()

# crop to left to right corners for reach row
def crop(im, height, width):
    array = bytearray()
    imgwidth, imgheight = im.size
    for i in range(0,imgheight,height):
        for j in range(0,imgwidth,width):
            box = (j, i, j+width, i+height)
            array += im.crop(box).tobytes()
        
    return array.hex()[::-2][::-1]

@App.get('/')

def get_screenshot():
    # Debugging
    debug = False
    s = perf_counter()

    # Take a screenshot
    scr = Webbie.takepicture()
    # Open with pillow
    scr = Image.frombytes('RGB',scr.size,scr.bgra, "raw", "BGRX")
    #Resize it
    s_1 = perf_counter()
    scr = scr.resize(( TOT_CC_WIDTH, TOT_CC_HEIGHT ),resample=Image.NEAREST)
    e_1 = perf_counter()
    # Quantize it to computercraft's colors
    s_2 = perf_counter()
    scr = scr.quantize(palette=pal_im,dither=1,method=2)
    e_2 = perf_counter()
    # Split the image into n pieces in a left corner to right corner 
    s_3 = perf_counter()
    fin = crop(scr,IND_CC_HEIGHT,IND_CC_WIDTH)
    e_3 = perf_counter()

    e = perf_counter()

    if debug:
        print( 
            "debug:" + "\n", 
            "resizing:" + str(e_1-s_1) + "\n" ,
            "quantize:" + str(e_2-s_2) + "\n",
            "cropping:" + str(e_3-s_3) + "\n",
            "overall:" + str(e-s) + "\n"
        )
    if e-s > 1/20:
        print("Capture is below the " + str(1/20) + " target.")
        print(e-s)
    # Reminder to press q to exit
    print("press q to exit")
    return Response(content=fin)

def aysnc_set(q):
    Webbie.seturl(q)

@App.get('/seturl/')

def set_url(q: str):
    # Run as thread since this blocking
    Thread(target=aysnc_set,args=(q,)).start()

@App.get("/click/{x}&{y}")

def click(x : int,y : int):
    # Click the screen
    Webbie.click(x,y)

@App.get("/type/{x}")

def press(x):
    # Type
    Webbie.keypress(x)
# set width height configuration
@App.get("/setind/{width}&{height}&{f}")
def set(width : int, height : int, f : int):
    global IND_CC_WIDTH,IND_CC_HEIGHT
    global TOT_CC_WIDTH,TOT_CC_HEIGHT
    if f == 0:
        IND_CC_WIDTH = width
        IND_CC_HEIGHT = height
    elif f == 1:
        TOT_CC_WIDTH = width
        TOT_CC_HEIGHT = height
# 
cfg=uvicorn.Config(App,host='0.0.0.0',port=PORT,access_log=False)
Server = Uvicorn_Server(config=cfg)
Server.run_uvi()

def grace_exit():
    import sys
    print("exiting")
    Server.kill_uvi()
    Webbie.exit()
    print("Finished")
    vdisplay.stop()
    sys.exit(0)

while True:
    # Remind to press q to exit
    print("press q to exit")
    key = input()
    if key == "q":
        grace_exit()