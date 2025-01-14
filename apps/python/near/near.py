# Name:       SubStanding for Assetto Corsa
# Version:    v1.1
# Anthor:     Sylvain Villet
# Contact:    sylvain.villet@gmail.com
# Date:       22.09.2017
# Desc.:      This app provides standings and positions
#             in a subgroup of the cars, that can be
#             the same car as the player or a class like
#             LMP1, GT2, GT3 etc defined here.
#             It also provides the global standing with
#             the same design (max 36 cars).
#             The app can be fully configured from the SubStanding_config widget.
# 
#             Feel free to add, remove or modify the "classes"
#             definitions in the Substanding_classes/classes.ini file.
# 
# Thanks:     - Rombik for the sim_info module
#             - Rivali (OV1Info) and Fernando Deutsch (ferito-LiveCarTracker)
#             for the inspiration and example
#             - ExOAte for the beta tests and ideas

import sys
import platform
import os
import configparser

import ac
import acsys

# Global
updateTime = 200

showLogo = 0
showTitle = 0
opacity = 50
showBorder = 1
showBadge = 1
colorAt = 250
unit = "metric"

fontSizeName = 12
fontSizeTitle = 8
fontSizeTime = 16
fontSizeGap = 28

zoom = 1

#Classes from the classes.ini file
classes = []

# Global variables
spacing = 5
firstSpacing = 30
fontSizeConfig = 16

maxDriverCount = 32

driversFullList =[]
myDriver = 0
trackLength = 0
lastUpdateTime = 0

badge=[]

nearApp = 0

config = 0
classesConfig = 0
configApp = 0

# ac.log("Near: is starting!")

try:
    if platform.architecture()[0] == "64bit":
        sysdir = os.path.dirname(__file__)+'/stdlib64'
        # ac.log("Near: sysdir 64!")
    else:
        sysdir = os.path.dirname(__file__)+'/stdlib'
        # ac.log("Near: sysdir not 64!")

    # ac.log("Near: sysdir: %s" % sysdir)

    sys.path.insert(0, sysdir)

    # ac.log("Near: sys.path: %s" % sys.path)

    os.environ['PATH'] = os.environ['PATH'] + ";."

    # ac.log("Near: os.path: %s" % os.environ['PATH'])

    from near_lib.sim_info import info

    # ac.log("Near: after info")
except Exception as e:
    ac.log("Near: Error importing libraries: %s" % e)
    raise


def acMain(ac_version):
    ac.log("Near: is Here!")
    try:
        global trackLength, nearApp
        global config, classesConfig, configApp
        global updateTime
        global showLogo, showTitle, opacity, showBorder, colorAt, unit
        global badge, showBadge
        global fontSizeName, fontSizeTitle, fontSizeTime, fontSizeGap, zoom
        global maxDriverCount
        global myDriver, driversFullList

        config = configparser.ConfigParser()
        config.read("apps/python/near/config/config.ini")

        # Global
        updateTime = config.getint("GLOBAL", "updateTime")

        showLogo  = config.getint("GLOBAL", "showLogo")
        showTitle = config.getint("GLOBAL", "showTitle")
        
        fontSizeName  = config.getint("GLOBAL", "fontSizeName")
        fontSizeTitle  = config.getint("GLOBAL", "fontSizeTitle")
        fontSizeTime  = config.getint("GLOBAL", "fontSizeTime")
        fontSizeGap  = config.getint("GLOBAL", "fontSizeGap")
        
        zoom  = config.getfloat("GLOBAL", "zoom")
        
        opacity   = config.getint("GLOBAL", "opacity")
        showBorder = config.getint("GLOBAL", "showBorder")
        showBadge = config.getint("GLOBAL", "showBadge")
        colorAt   = config.getint("GLOBAL", "colorAt")
        unit      = config.get("GLOBAL", "unit")

        # Get classes
        classesConfig = configparser.ConfigParser()
        classesConfig.read("apps/python/near/classes/classes.ini")

        for eachSection in classesConfig.sections():
            classTmp = []
            classTmp.append(eachSection)
            for eachItem in classesConfig.items(eachSection):
                classTmp.append(eachItem[1])
            classes.append(classTmp)

        maxDriverCount = ac.getCarsCount()

        # Get badges
        for i in range(maxDriverCount):
            carName = ac.getCarName(i)
            if type(carName) == type(""):
                textureId = ac.newTexture("content/cars/" + carName + "/ui/badge.png")
                if textureId >= 0:
                    badge.append(textureId)
                else:
                    badge.append(-1)
            else:
                badge.append(-1)

        nearApp = NearWindow("Near", "Near")

        configApp = Near_config("Near_config", "Near config", fontSizeConfig)
        configApp.updateView()

        ac.addRenderCallback(configApp.window, onRenderCallbackConfig)

        trackLength = ac.getTrackLength(0)

        # Get all needed infos
        for index in range(maxDriverCount):
            driver = {
                "carId":        index, 
                "connected":    ac.isConnected(index),
                "driverName":   ac.getDriverName(index), 
                "carName":      ac.getCarName(index),
                "bestLap":      ac.getCarState(index, acsys.CS.BestLap),
                "lapTime":      ac.getCarState(index, acsys.CS.LapTime), 
                "lastLapTime":  ac.getCarState(index, acsys.CS.LastLap), 
                "lapCount":     ac.getCarState(index, acsys.CS.LapCount), 
                "lapPosition":  ac.getCarState(index, acsys.CS.NormalizedSplinePosition),
                "speedMS":      ac.getCarState(index, acsys.CS.SpeedMS), 
                "distance":     ac.getCarState(index, acsys.CS.LapCount) + ac.getCarState(index, acsys.CS.NormalizedSplinePosition),
                "tyres":        ac.getCarTyreCompound(index), 
                "isInPit":      ac.isCarInPit(index), 
                "isInPitLine":  ac.isCarInPitline(index),
                "pitStops":     0,
                "pitEntryFlag": False,
                "raceStartFlag":True,
                "state":        0
            }
            if index == 0:
                myDriver = driver

            driversFullList.append(driver)

        # ac.log("Near: AC Main - END")
        return "near"
    except Exception as e:
        ac.log("Near: Error in acMain: %s" % e)

def acUpdate(deltaT):
    # ac.log("Near: AC Update")
    try:
        global myDriver, lastUpdateTime, driversFullList

        lastUpdateTime += deltaT

        if lastUpdateTime < float(updateTime)/1000:
            # ac.log("Near: AC Update - END by time")
            return

        lastUpdateTime = 0

        driversList = []
        driversCount = info.static.numCars

        globalStanding = []

        # Get all needed infos
        for index in range(driversCount):
            driver = driversFullList[index]
            driver["connected"]   = ac.isConnected(index)
            driver["driverName"]  = ac.getDriverName(index)
            driver["carName"]     = ac.getCarName(index)
            driver["bestLap"]     = ac.getCarState(index, acsys.CS.BestLap)
            driver["lapTime"]     = ac.getCarState(index, acsys.CS.LapTime)
            driver["lastLapTime"] = ac.getCarState(index, acsys.CS.LastLap)
            driver["lapCount"]    = ac.getCarState(index, acsys.CS.LapCount)
            driver["lapPosition"] = ac.getCarState(index, acsys.CS.NormalizedSplinePosition)
            driver["speedMS"]     = ac.getCarState(index, acsys.CS.SpeedMS)
            driver["distance"]    = ac.getCarState(index, acsys.CS.LapCount) + ac.getCarState(index, acsys.CS.NormalizedSplinePosition)
            driver["tyres"]       = ac.getCarTyreCompound(index)
            driver["isInPit"]     = ac.isCarInPit(index)

            isInPitLine = ac.isCarInPitline(index)

            # Race
            if info.graphics.session == 2:
                # Trying to resolve the race start problem
                if driver["raceStartFlag"] and driver["lapCount"] == 0:
                    if driver["distance"] > 0.7:
                        driver["distance"] -= 1.0
                    elif driver["distance"] > 0.3:
                        driver["raceStartFlag"] = False
                    
                    driver["pitStops"] = 0
                else:
                    driver["raceStartFlag"] = False

                # Pit entry
                if isInPitLine and not driver["isInPitLine"]:
                    driver["pitEntryFlag"] = True
                # Pit exit
                elif driver["pitEntryFlag"] and not isInPitLine and driver["isInPitLine"]:
                    driver["pitEntryFlag"] = False
                    driver["pitStops"] += 1
            else:
                driver["pitStops"] = 0
                driver["raceStartFlag"] = True

            driver["isInPitLine"] = isInPitLine

            if index == 0:
                myDriver = driver
                driversList.append(driver)
            elif driver["connected"] == 1:
                driversList.append(driver)

            driversFullList[index] = driver

        driversCount = len(driversList)

        # Sort the global standing by distance or best lap
        # Race
        if info.graphics.session == 2:
            #sort by distance
            driversList.sort(key=lambda tup: tup["distance"], reverse=True)
            globalStanding = driversList
        # Practice, qualif
        else:
            driversList.sort(key=lambda tup: tup["lapPosition"], reverse=True)
            globalStanding = driversList

        nearApp.updateView(globalStanding)

        configApp.updateView()

        # ac.log("Near: AC Update - END")

    except Exception as e:
        ac.log("Near: Error in acUpdate: %s" % e)

def timeToString(time):
    if time <= 0 or time == 9999999:
        return "-:--.---"
    else:
        return "{:d}:{:0>2d}.{:0>3d}".format(int(time/60000), int((time%60000)/1000), time%1000)

def deltaToLabel(label, delta, speedAvg):
    if delta > 100:
        delta = 0

    distance = delta*trackLength

    if delta < 1 and delta > -1 and trackLength > 0:
        if unit == "metric":
            ac.setText(label, "{:+.0f}  m".format(distance))
        elif unit == "imperial":
            if distance < 1609:
                ac.setText(label, "{:+.0f}  ft".format(distance*3.28))
            else:
                ac.setText(label, "{:+.1f}  mi".format(distance/1609))
        elif unit == "time":
            if speedAvg < 15:
                speedAvg = 15
            deltaTime = -distance/speedAvg
            ac.setText(label, "{:+.1f}  s".format(deltaTime))

    elif delta < 2 and delta > -2:
        ac.setText(label, "{:+.1f}  lap".format(delta))
    else:
        ac.setText(label, "{:+.1f}  laps".format(delta))

    ac.setFontColor(label, 1, 1, 1, 1)

class NearWindow:

    def __init__(self, name, headerName):
        # ac.log("Near: NearWindow constructor")
        try:
            self.headerName = headerName
            self.window = ac.newApp(name)

            self.positionLabel = []
            self.nameLabel = []
            self.lastTimeTitleLabel = []
            self.lastTimeLabel = []
            self.bestTimeTitleLabel = []
            self.bestTimeLabel = []
            self.gapTimeLabel = []

            for index in range(2):
                self.positionLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.positionLabel[index], 'left')

                self.nameLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.nameLabel[index], 'left')

                self.lastTimeTitleLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.lastTimeTitleLabel[index], 'left')

                self.lastTimeLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.lastTimeLabel[index], 'left')

                self.bestTimeTitleLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.bestTimeTitleLabel[index], 'left')

                self.bestTimeLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.bestTimeLabel[index], 'left')

                self.gapTimeLabel.append(ac.addLabel(self.window, ""))
                ac.setFontAlignment(self.gapTimeLabel[index], 'right')


            self.refreshParameters()
        except Exception as e:
            ac.log("Near: Error in NearWindow constructor: %s" % e)

    def refreshParameters(self):
        # ac.log("Near: NearWindow refreshParameters")
        if showLogo:
            ac.setIconPosition(self.window, 0, 0)
        else:
            ac.setIconPosition(self.window, -10000, -10000)

        if showTitle:
            ac.setTitle(self.window, self.headerName)
        else:
            ac.setTitle(self.window, "")

        if showLogo or showTitle:
            self.firstSpacing = firstSpacing
        else:
            self.firstSpacing = 0

        self.widthPositionLabel = 2*fontSizeName*zoom
        self.heightDriverHeaderLabel = fontSizeName*zoom

        self.widthGap = 3*fontSizeGap*zoom
        self.heightGap = 3*fontSizeGap*zoom

        self.vSpaceTime = 0.25*fontSizeTime*zoom

        self.width = 2*self.widthGap
        self.height = self.firstSpacing + 2*(fontSizeName*zoom + self.heightGap) + self.vSpaceTime

        for index in range(2):

            # self.positionLabel = []
            # self.nameLabel = []
            # self.beforeTimeTitleLabel = []
            # self.beforeTimeLabel = []
            # self.bestTimeTitleLabel = []
            # self.bestTimeLabel = []
            # self.gapTimeLabel = []

            ac.setFontSize(self.positionLabel[index], fontSizeName*zoom)
            ac.setSize(self.positionLabel[index], self.widthPositionLabel, fontSizeName*zoom)
            ac.setVisible(self.positionLabel[index], 1)

            ac.setFontSize(self.nameLabel[index], fontSizeName*zoom)
            ac.setSize(self.nameLabel[index], fontSizeName*10*zoom, fontSizeName*zoom)
            ac.setVisible(self.nameLabel[index], 1)

            ac.setText(self.lastTimeTitleLabel[index], 'LAST')
            ac.setFontColor(self.lastTimeTitleLabel[index], 0.314, 0.337, 0.369, 1)
            ac.setFontSize(self.lastTimeTitleLabel[index], fontSizeTitle*zoom)
            ac.setSize(self.lastTimeTitleLabel[index], fontSizeTitle*4*zoom, fontSizeTitle*zoom)
            ac.setVisible(self.lastTimeTitleLabel[index], 1)

            ac.setText(self.bestTimeTitleLabel[index], 'BEST')
            ac.setFontColor(self.bestTimeTitleLabel[index], 0.314, 0.337, 0.369, 1)
            ac.setFontSize(self.bestTimeTitleLabel[index], fontSizeTitle*zoom)
            ac.setSize(self.bestTimeTitleLabel[index], fontSizeTitle*4*zoom, fontSizeTitle*zoom)
            ac.setVisible(self.bestTimeTitleLabel[index], 1)

            ac.setFontSize(self.lastTimeLabel[index], fontSizeTime*zoom)
            ac.setSize(self.lastTimeLabel[index], fontSizeTime*7*zoom, fontSizeTime*zoom)
            ac.setVisible(self.lastTimeLabel[index], 1)

            ac.setFontSize(self.bestTimeLabel[index], fontSizeTime*zoom)
            ac.setSize(self.bestTimeLabel[index], fontSizeTime*7*zoom, fontSizeTime*zoom)
            ac.setVisible(self.bestTimeLabel[index], 1)

            ac.setFontSize(self.gapTimeLabel[index], fontSizeGap*zoom)
            ac.setSize(self.gapTimeLabel[index], self.widthGap, fontSizeGap*zoom)
            ac.setVisible(self.gapTimeLabel[index], 1)
            

        #Driver ahead
        ac.setPosition(self.positionLabel[0], 0 , self.firstSpacing)
        ac.setPosition(self.nameLabel[0], self.widthPositionLabel , self.firstSpacing)
        ac.setPosition(self.lastTimeTitleLabel[0], 0 , self.firstSpacing + self.heightDriverHeaderLabel + 0.5*self.heightGap - fontSizeTitle*zoom - fontSizeTime*zoom - self.vSpaceTime)
        ac.setPosition(self.lastTimeLabel[0], 0 , self.firstSpacing + self.heightDriverHeaderLabel + 0.5*self.heightGap - fontSizeTime*zoom - self.vSpaceTime)
        ac.setPosition(self.bestTimeTitleLabel[0], 0 , self.firstSpacing + self.heightDriverHeaderLabel + 0.5*self.heightGap + self.vSpaceTime)
        ac.setPosition(self.bestTimeLabel[0], 0 , self.firstSpacing + self.heightDriverHeaderLabel + 0.5*self.heightGap + fontSizeTitle*zoom + self.vSpaceTime)
        ac.setPosition(self.gapTimeLabel[0], self.widthGap , self.firstSpacing + self.heightDriverHeaderLabel + 0.5*self.heightGap - fontSizeTitle*zoom - fontSizeTime*zoom)

        #Driver behind
        ac.setPosition(self.lastTimeTitleLabel[1], 0 , self.firstSpacing + self.heightDriverHeaderLabel + self.heightGap + 0.5*self.heightGap - fontSizeTitle*zoom - fontSizeTime*zoom - self.vSpaceTime)
        ac.setPosition(self.lastTimeLabel[1], 0 , self.firstSpacing + self.heightDriverHeaderLabel + self.heightGap + 0.5*self.heightGap - fontSizeTime*zoom - self.vSpaceTime)
        ac.setPosition(self.bestTimeTitleLabel[1], 0 , self.firstSpacing + self.heightDriverHeaderLabel + self.heightGap + 0.5*self.heightGap + self.vSpaceTime)
        ac.setPosition(self.bestTimeLabel[1], 0 , self.firstSpacing + self.heightDriverHeaderLabel + self.heightGap + 0.5*self.heightGap + fontSizeTitle*zoom + self.vSpaceTime)
        ac.setPosition(self.gapTimeLabel[1], self.widthGap , self.firstSpacing + self.heightDriverHeaderLabel + self.heightGap + 0.5*self.heightGap - fontSizeTitle*zoom - fontSizeTime*zoom)
        ac.setPosition(self.positionLabel[1], 0 , self.firstSpacing + self.heightDriverHeaderLabel + 2*self.heightGap)
        ac.setPosition(self.nameLabel[1], self.widthPositionLabel , self.firstSpacing + self.heightDriverHeaderLabel + 2*self.heightGap)

        # Adjust window size, opacity and border
        ac.setSize(self.window, self.width, self.height)
        ac.setBackgroundOpacity(self.window, float(opacity)/100)
        ac.drawBorder(self.window, showBorder)

        # ac.log("Near: NearWindow refreshParameters - END")

    def updateView(self, standing):
        # ac.log("Near: NearWindow updateView")
        try:

            myIndex = standing.index(myDriver)
            aheadIndex = myIndex - 1
            behindIndex = myIndex + 1

            # We are first
            if myIndex == 0:
                aheadIndex = len(standing) - 1
            # We are last
            elif myIndex == len(standing) - 1:
                behindIndex = 0

            ac.setText(self.positionLabel[0], "{0}.".format(aheadIndex+1))
            ac.setText(self.positionLabel[1], "{0}.".format(behindIndex+1))

            ac.setText(self.nameLabel[0], standing[aheadIndex]["driverName"])
            ac.setText(self.nameLabel[1], standing[behindIndex]["driverName"])

            deltaToLabel(self.gapTimeLabel[0], standing[aheadIndex]["distance"] - myDriver["distance"], (standing[aheadIndex]["speedMS"] + myDriver["speedMS"])/2)
            deltaToLabel(self.gapTimeLabel[1], standing[behindIndex]["distance"] - myDriver["distance"], (standing[aheadIndex]["speedMS"] + myDriver["speedMS"])/2)

            ac.setText(self.bestTimeLabel[0], timeToString(standing[aheadIndex]["bestLap"]))
            ac.setText(self.bestTimeLabel[1], timeToString(standing[behindIndex]["bestLap"]))

            ac.setText(self.lastTimeLabel[0], timeToString(standing[aheadIndex]["lastLapTime"]))
            ac.setText(self.lastTimeLabel[1], timeToString(standing[behindIndex]["lastLapTime"]))

            # ac.log("Near: NearWindow updateView - END")
        except Exception as e:
            ac.log("Near: Error in NearWindow.updateView: %s" % e)


class Near_config:

    def __init__(self, name, headerName, fontSize):
        self.window = ac.newApp(name)
        ac.setTitle(self.window, headerName)

        widthLeft       = fontSize*8
        widthCenter     = fontSize*5
        widthRight      = fontSize*5
        width           = widthLeft + widthCenter + widthRight + 2*spacing
        height          = firstSpacing + (fontSize*1.5 + spacing)*11

        ac.setSize(self.window, width, height)

        self.leftLabel = []
        self.centerLabel = []
        self.changeButton = []
        self.plusButton = []
        self.minusButton = []

        for index in range(11):
            self.leftLabel.append(ac.addLabel(self.window, ""))
            ac.setFontSize(self.leftLabel[index], fontSize)
            ac.setPosition(self.leftLabel[index], spacing, firstSpacing + index*(fontSize*1.5+spacing))
            ac.setSize(self.leftLabel[index], widthLeft, fontSize+spacing)
            ac.setFontAlignment(self.leftLabel[index], 'left')

            self.centerLabel.append(ac.addLabel(self.window, ""))
            ac.setFontSize(self.centerLabel[index], fontSize)
            ac.setPosition(self.centerLabel[index], spacing + widthLeft, firstSpacing + index*(fontSize*1.5+spacing))
            ac.setSize(self.centerLabel[index], widthCenter, fontSize+spacing)
            ac.setFontAlignment(self.centerLabel[index], 'left')

            self.changeButton.append(ac.addButton(self.window, "Change"))
            ac.setFontSize(self.changeButton[index], fontSize)
            ac.setPosition(self.changeButton[index], spacing + widthLeft + widthCenter, firstSpacing + index*(fontSize*1.5+spacing))
            ac.setSize(self.changeButton[index], fontSize*4, fontSize*1.5)

            self.plusButton.append(ac.addButton(self.window, "+"))
            ac.setFontSize(self.plusButton[index], fontSize)
            ac.setPosition(self.plusButton[index], spacing + widthLeft + widthCenter, firstSpacing + index*(fontSize*1.5+spacing))
            ac.setSize(self.plusButton[index], fontSize*1.5, fontSize*1.5)

            self.minusButton.append(ac.addButton(self.window, "-"))
            ac.setFontSize(self.minusButton[index], fontSize)
            ac.setPosition(self.minusButton[index], spacing + widthLeft + widthCenter + fontSize*2.5, firstSpacing + index*(fontSize*1.5+spacing))
            ac.setSize(self.minusButton[index], fontSize*1.5, fontSize*1.5)

        rowIndex = 0

        ac.setText(self.leftLabel[rowIndex], "Global:")
        ac.setVisible(self.changeButton[rowIndex], 0)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Show AC logo:")
        ac.addOnClickedListener(self.changeButton[rowIndex], toggleLogo)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)
        self.showLogoId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Show title:")
        ac.addOnClickedListener(self.changeButton[rowIndex], toggleTitle)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)
        self.showTitleId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Font size:")
        ac.setVisible(self.changeButton[rowIndex], 0)
        ac.addOnClickedListener(self.plusButton[rowIndex], fontSizePlus)
        ac.addOnClickedListener(self.minusButton[rowIndex], fontSizeMinus)
        self.fontSizeId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Opacity:")
        ac.setVisible(self.changeButton[rowIndex], 0)
        ac.addOnClickedListener(self.plusButton[rowIndex], opacityPlus)
        ac.addOnClickedListener(self.minusButton[rowIndex], opacityMinus)
        self.opacityId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Show border:")
        ac.addOnClickedListener(self.changeButton[rowIndex], toggleBorder)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)
        self.showBorderId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Show badges:")
        ac.addOnClickedListener(self.changeButton[rowIndex], toggleBadge)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)
        self.showBadgeId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Units:")
        ac.addOnClickedListener(self.changeButton[rowIndex], toggleUnits)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)
        self.unitsId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Color distance:")
        ac.setVisible(self.changeButton[rowIndex], 0)
        ac.addOnClickedListener(self.plusButton[rowIndex], colorAtPlus)
        ac.addOnClickedListener(self.minusButton[rowIndex], colorAtMinus)
        self.colorAtId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Show border:")
        ac.addOnClickedListener(self.changeButton[rowIndex], toggleBorderPos)
        ac.setVisible(self.plusButton[rowIndex], 0)
        ac.setVisible(self.minusButton[rowIndex], 0)
        self.showBorderPosId = rowIndex

        rowIndex += 1

        ac.setText(self.leftLabel[rowIndex], "Refresh every:")
        ac.setVisible(self.changeButton[rowIndex], 0)
        ac.addOnClickedListener(self.plusButton[rowIndex], refreshPlus)
        ac.addOnClickedListener(self.minusButton[rowIndex], refreshMinus)
        self.refreshId = rowIndex

    def updateView(self):
        ac.setText(self.centerLabel[self.showLogoId],  yesOrNo(showLogo))
        ac.setText(self.centerLabel[self.showTitleId], yesOrNo(showTitle))
        ac.setText(self.centerLabel[self.fontSizeId],  "{:.1f}".format(zoom))
        ac.setText(self.centerLabel[self.opacityId],   "{0} %".format(opacity))
        ac.setText(self.centerLabel[self.showBorderId], yesOrNo(showBorder))
        ac.setText(self.centerLabel[self.showBadgeId], yesOrNo(showBadge))

        if unit == "metric":
            ac.setText(self.centerLabel[self.unitsId], "Metric")
            ac.setText(self.centerLabel[self.colorAtId], "{0} m".format(colorAt))
        elif unit == "imperial":
            ac.setText(self.centerLabel[self.unitsId], "Imperial")
            ac.setText(self.centerLabel[self.colorAtId], "{:.0f} ft".format(colorAt*3.28))
        elif unit == "time":
            ac.setText(self.centerLabel[self.unitsId], "Time (est)")
            ac.setText(self.centerLabel[self.colorAtId], "{0} m".format(colorAt))

        if updateTime == 0:
            ac.setText(self.centerLabel[self.refreshId], "Min")
        elif updateTime == 50:
            ac.setText(self.centerLabel[self.refreshId], "0.05 s")
        else:
            ac.setText(self.centerLabel[self.refreshId], "{:.1f} s".format(float(updateTime)/1000))

    def onRenderCallback(self, deltaT):
        ac.setBackgroundOpacity(self.window, 1.0)

def yesOrNo(value):
    if value:
        return "Yes"
    else:
        return "No"

def toggleLogo(dummy, variable):
    global showLogo

    if showLogo:
        showLogo = 0
    else:
        showLogo = 1

    refreshAndWriteParameters()

def toggleTitle(dummy, variable):
    global showTitle

    if showTitle:
        showTitle = 0
    else:
        showTitle = 1

    refreshAndWriteParameters()

def fontSizePlus(dummy, variable):
    global zoom

    zoom += 0.1

    refreshAndWriteParameters()

def fontSizeMinus(dummy, variable):
    global zoom

    if zoom > 0:
        zoom -= 0.1

    refreshAndWriteParameters()

def toggleBorder(dummy, variable):
    global showBorder

    if showBorder:
        showBorder = 0
    else:
        showBorder = 1

    refreshAndWriteParameters()

def toggleTyres(dummy, variable):
    global showTyres

    if showTyres:
        showTyres = 0
    else:
        showTyres = 1

    refreshAndWriteParameters()

def togglePitStops(dummy, variable):
    global showPitStops

    if showPitStops:
        showPitStops = 0
    else:
        showPitStops = 1

    refreshAndWriteParameters()

def toggleBadge(dummy, variable):
    global showBadge

    if showBadge:
        showBadge = 0
    else:
        showBadge = 1

    refreshAndWriteParameters()

def opacityPlus(dummy, variable):
    global opacity

    if opacity < 100:
        opacity += 10

    refreshAndWriteParameters()

def opacityMinus(dummy, variable):
    global opacity

    if opacity >= 10:
        opacity -= 10

    refreshAndWriteParameters()

def toggleDelta(dummy, variable):
    global showDelta

    if showDelta:
        showDelta = 0
    else:
        showDelta = 1

    refreshAndWriteParameters()

def colorAtPlus(dummy, variable):
    global colorAt

    if colorAt < 2000:
        colorAt += 50

    refreshAndWriteParameters()

def colorAtMinus(dummy, variable):
    global colorAt

    if colorAt >= 100:
        colorAt -= 50

    refreshAndWriteParameters()

def toggleUnits(dummy, variable):
    global unit

    if unit == "metric":
        unit = "imperial"
    elif unit == "imperial":
        unit = "time"
    elif unit == "time":
        unit = "metric"

    refreshAndWriteParameters()

def toggleBorderPos(dummy, variable):
    global showBorderPos

    if showBorderPos:
        showBorderPos = 0
    else:
        showBorderPos = 1

    refreshAndWriteParameters()

def refreshPlus(dummy, variable):
    global updateTime

    if updateTime == 0:
        updateTime = 50
    elif updateTime == 50:
        updateTime = 100
    elif updateTime < 1000:
        updateTime += 100
    else:
        updateTime = 1000

    refreshAndWriteParameters()

def refreshMinus(dummy, variable):
    global updateTime

    if updateTime == 50:
        updateTime = 0
    elif updateTime == 100:
        updateTime = 50
    elif updateTime > 100:
        updateTime -= 100
    else:
        updateTime = 0

    refreshAndWriteParameters()

def refreshAndWriteParameters():
    try:
        nearApp.refreshParameters()

        configApp.updateView()
        writeParameters()

    except Exception as e:
        ac.log("Near: Error in refreshAndWriteParameters: %s" % e)

def writeParameters():
    try:
        config.set("GLOBAL", "updateTime", str(updateTime))

        config.set("GLOBAL", "showLogo", str(showLogo))
        config.set("GLOBAL", "showTitle", str(showTitle))
        
        config.set("GLOBAL", "fontSizeName", str(fontSizeName))
        config.set("GLOBAL", "fontSizeTitle", str(fontSizeTitle))
        config.set("GLOBAL", "fontSizeTime", str(fontSizeTime))
        config.set("GLOBAL", "fontSizeGap", str(fontSizeGap))
        
        config.set("GLOBAL", "zoom", str(zoom))
        
        config.set("GLOBAL", "opacity", str(opacity))
        config.set("GLOBAL", "showBorder", str(showBorder))
        config.set("GLOBAL", "colorAt", str(colorAt))
        config.set("GLOBAL", "unit", str(unit))

        configFile = open("apps/python/near/config/config.ini", 'w')
        config.write(configFile)
        configFile.close()

    except Exception as e:
        ac.log("Near: Error in writeParameters: %s" % e)

def onRenderCallbackConfig(deltaT):
    try:
        configApp.onRenderCallback(deltaT)
    except Exception as e:
        ac.log("Near: Error in onRenderCallbackConfig: %s" % e)