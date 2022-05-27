local monitors = {}
local sub = string.sub
local sleep = os.sleep
local scaledw,scaledh
local totw,toth
local virt,horiz
local monitor_count
--
local function round(x) return math.floor(x+0.5) end

local function setup_monitors()

    local function table_find(tbl,str)
        for i,v in ipairs(tbl) do
            if v == str then return i end
        end
        return false
    end
    -- Get all monitors connected
    local monitor = {peripheral.find("monitor")}
    -- Set the textscale to 1, set to white and clear
    for i=1,#monitor do 
        monitor[i].setTextScale(1);
        monitor[i].setBackgroundColor(colors.white) 
        monitor[i].clear()
    end
    print("Monitor Setup")
    print("Click the monitors from left to right for each row, starting from the top left")
    while true do
        -- wait to touch event..
        event,side,x,y = os.pullEvent("monitor_touch")
        -- check if monitor exists in table
        local check_if_monitor = table_find(monitors,side) 
        --
        if check_if_monitor then
            table.remove(monitors,check_if_monitor)
            local mon = peripheral.wrap(side)
            mon.setBackgroundColor(colors.white)
            mon.clear()
        else
            table.insert(monitors,side)
            local mon = peripheral.wrap(side)
            mon.setBackgroundColor(colors.orange)
            mon.clear()
        end
        --
        if #monitors == #monitor then
            print("Finish!")
            -- set all monitors to black and prepare the monitors table
            for i=1,#monitors do monitors[i] = {monitors[i],peripheral.wrap(monitors[i]) }; peripheral.wrap(monitors[i][1]).setBackgroundColor(colors.black); peripheral.wrap(monitors[i][1]).clear() end
            print("Please specify the column of monitors")
            virt = tonumber(io.read())
            print("Please specify the row of monitors")
            horiz = tonumber(io.read())
            local check = fs.exists("cc_wd") or fs.makeDir("cc_wd")
            print("Enter your configuration name:")
            local filename = "cc_wd/"..io.read()
            -- open up a text file 
            local check = fs.exists(filename)
            if check then fs.delete(filename) end
            local file = fs.open(filename,"w")
            file.writeLine(tostring(virt))
            file.writeLine(tostring(horiz))
            --
            for i=1,#monitors do 
                file.writeLine(monitors[i][1])
            end
            --
            file.close()
            print("Saved")
            break
            --
        end
    end
end

local function main()
    local single_frame_bytes 
    local width,height
    local httpget = http.get
    monitor_count = #monitors
    -- reset
    for i=1,monitor_count do
        monitors[i][2].setTextScale(1)
        monitors[i][2].setBackgroundColor(colors.white) 
        monitors[i][2].clear()
    end
    --
    while true do
        --
        print("What scale should all monitors use")
        local scale =  tonumber(io.read())
        -- get first monitor
        width,height = monitors[1][2].getSize()
        scaledw,scaledh = round(width/scale),round(height/scale)
        totw,toth = scaledw*horiz,scaledh*virt
        print("A single monitor's scaled resolution is")
        print(tostring(scaledw).."x"..tostring(scaledh))
        print("The TOTAL scaled resolution across all monitors would be")
        print(tostring(totw).."x"..tostring(toth))
        print("Is this correct?")
        --
        local cor = io.read()
        if cor == "y" or cor == "yes" then
            print("contacting the server to set the resolutions")
            --
            local handle  = httpget("http://127.0.0.1:5001/setind/"..tostring(scaledw).."&"..tostring(scaledh).."&".."0")
            handle.close()
            --
            local handle  = httpget("http://127.0.0.1:5001/setind/"..tostring(totw).."&"..tostring(toth).."&".."1")
            handle.close()
            --
            for i=1,monitor_count do
                local sf = pcall(
                    function()
                        monitors[i][2].setTextScale(scale)
                    end
                )
                if not sf then
                    error("There was an issue setting the text scale.")
                end
            end
            --
            single_frame_bytes = scaledw*scaledh
            width,height = scaledw,scaledh
            break
            --
        end

        
    end
    --
    while true do
        -- get current frame
        local bench bench = os.clock()
        local handle  = httpget("http://127.0.0.1:5001/")
	    local f = handle.readAll()
        handle.close()

        for m=0,monitor_count-1 do
            --
            for i=1,height do
                --
                row =  sub(f, single_frame_bytes*m+ (1 + (width * (i-1) ) ) , (width*i) + single_frame_bytes*m  )
                monitors[m+1][2].setCursorPos(1,i)
                monitors[m+1][2].blit(row,row,row)           
                row = nil
                --
            end
            --
        end

        f = nil
        sleep()
  end
end

local function keyint()
    local function SendToHTTP(URI)
        local handle  = http.get(URI,nil,true)
        handle.close()
        return data
    end
    while true do 
        local event, key = os.pullEvent("key")
        if key == keys.u then
            print("New Url:")
            url = io.read()
            SendToHTTP("http://127.0.0.1:5001/seturl/?q="..url)
            os.sleep(2)
        end
        if key == keys.q then
            error("quit.")
        end
    end
end

local function montouch()
    local function SendToHTTP(URI)
        local handle  = http.get(URI,nil,true)
        handle.close()
    end
    --
    local monx,mony
    while true do
        --
        event,side,x,y = os.pullEvent("monitor_touch")
        local ratiox,ratioy = 1280/(totw),720/(toth)
        -- 
        for i=1,monitor_count do
            if monitors[i][1] == side then
                monx,mony =   ( ( i - 1) % horiz ) , math.floor(((i - 1 ) / horiz )) 
                break
            end
        end
        --
        newx,newy = x + (scaledw*monx),y + (scaledh*mony)
        newx,newy = round(newx*ratiox),round(newy*ratioy)
        SendToHTTP("http://127.0.0.1:5001/click/"..tostring(newx).."&"..tostring(newy))
   
    end
end

local function menu()
    while true do
        print(" [1] Start\n [2] Load configuration\n [3] Configure Monitors\n ")
        local inp = io.read()
        if inp == "1" then 
            if #monitors == 0 then
                print("You have not loaded a monitor configuration.")
            else
                parallel.waitForAll(main,keyint,montouch)
            end
        elseif inp == "2" then
           print("Listing configurations..")
           if not fs.exists("cc_wd") then
                print("You have not configured your montior(s) yet.")
           else
            local configs = fs.list("cc_wd")
            while true do 
                    for i=1,#configs do 
                        print(configs[i])
                    end
                    print("Choose your configuration")
                    local sel = "cc_wd/"..io.read()       
                    -- check 
                    if fs.exists(sel) then
                        -- get the first two lines, they are consistant 
                        local file = fs.open(sel,"r")
                        virt = tonumber(file.readLine())
                        horiz = tonumber(file.readLine())
                        -- we now read all the remaining lines
                
                        while true do 
                            local l = file.readLine()
                            if not l then print("Loaded!") break end
                            table.insert(monitors,{l,peripheral.wrap(l)})
                            
                        end
                        break
                    end
                end
            end
        elseif inp == "3" then
            term.clear()
            setup_monitors()
            print("Starting up..")
            
            parallel.waitForAll(main,keyint,montouch)
        else 
            print("quitting!")
            
            break
        end
        
    end
end

menu()
