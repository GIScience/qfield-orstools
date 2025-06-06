import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import QtQuick.Layouts


import org.qfield
import org.qgis
import Theme

import "qrc:/qml" as QFieldItems

Item {
  id: plugin
width: mainWindow.width
height: mainWindow.height

    property var mainWindow: iface.mainWindow()
  property var mapCanvas: iface.mapCanvas()
  property var canvasMenu: iface.findItemByObjectName('canvasMenu')

  Component.onCompleted: {
    iface.addItemToCanvasActionsToolbar(pluginButtonsContainer)
    iface.addItemToPluginsToolbar(settingsButton)
    }

    QfToolButton {
        id: settingsButton
        iconSource: 'icon.svg'
        iconColor: "white"
        bgcolor: "red"
        round: true

        onClicked: {
            mainWindow.displayToast(qsTr('Settings button clicked'))
            settingsDialog.open()
        }
    }

    Dialog {
        id: settingsDialog
        parent: mainWindow.contentItem

        title: "Settings"

        visible: false
        modal: true
        font: Theme.defaultFont

        z: 10000
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        Column {
            spacing: 12
            width: parent.width

            TextField {
                id: apiKeyField
                width: parent.width
                placeholderText: "Enter API key"
                text: settings.value("orstools/api_key", "")
            }

            ComboBox {
                id: profileSelector
                width: parent.width
                model: [
                    "driving-car",
                    "driving-hgv",
                    "cycling-regular",
                    "cycling-road",
                    "cycling-mountain",
                    "cycling-electric",
                    "foot-walking",
                    "foot-hiking",
                    "wheelchair",
                ]
                currentIndex: {
                    const saved = settings.value("orstools/profile", "driving-car")
                        model.indexOf(saved) >= 0 ? model.indexOf(saved) : 0
                }
            }
        }

        standardButtons: Dialog.Ok

        onAccepted: {
            settings.setValue("orstools/api_key", apiKeyField.text)
            settings.setValue("orstools/profile", profileSelector.currentText)
        }
    }




    Marker {
    id: startMarker
    parent: mapCanvas
    visible: routeStartPoint != undefined

    sourcePosition: routeStartPoint ? routeStartPoint : GeometryUtils.emptyPoint()
    sourceCrs: routeRenderer.geometryWrapper.crs
    destinationCrs: mapCanvas.mapSettings.destinationCrs
    fillColor: "green"
  }

  Marker {
    id: endMarker
    parent: mapCanvas
    visible: routeEndPoint != undefined

    sourcePosition: routeEndPoint ? routeEndPoint : GeometryUtils.emptyPoint()
    sourceCrs: routeRenderer.geometryWrapper.crs
    destinationCrs: mapCanvas.mapSettings.destinationCrs
    fillColor: "orangered"
  }

  QFieldItems.GeometryRenderer {
    id: routeRenderer
    parent: mapCanvas
    mapSettings: mapCanvas.mapSettings
    geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
    lineWidth: 6
    color: "#c62828"
  }

  Rectangle {
    id: pluginButtonsContainer
    width: childrenRect.width + 10
    height: 48
    radius: height / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0.0; color: "#015491" }
      GradientStop { position: 1.0; color: "#562b7a" }
    }

    QfToolButton {
      id: addStartPointButton
      anchors.left: parent.left
      anchors.leftMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      width: parent.height - 10
      height: width
      iconSource: 'routeStartIcon.svg'
      iconColor: "white"
      bgcolor: routeStartPoint != undefined ? "green" : "transparent"
      round: true

      onClicked: {
        routeStartPoint = GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs)
        if (routeEndPoint != undefined) {
          getRoute()
        }
        canvasMenu.close()
      }
    }

    QfToolButton {
      id: addEndPointButton
      anchors.left: addStartPointButton.right
      anchors.leftMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      width: parent.height - 10
      height: width
      iconSource: 'routeEndIcon.svg'
      iconColor: "white"
      bgcolor: routeEndPoint != undefined ? "orangered" : "transparent"
      round: true

      onClicked: {
        routeEndPoint = GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs)
        if (routeStartPoint != undefined) {
          getRoute()
        }
        canvasMenu.close()
      }
    }

    QfToolButton {
      id: clearPointsButton
      anchors.left: addEndPointButton.right
      anchors.leftMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      width: parent.height - 10
      height: width
      iconSource: 'routeClearIcon.svg'
      iconColor: "white"
      round: true
      enabled: routeStartPoint != undefined || routeEndPoint != undefined
      opacity: enabled ? 1.0 : 0.5

      onClicked: {
        routeStartPoint = undefined
        routeEndPoint = undefined
        routeRenderer.geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt("")
        canvasMenu.close()
      }
    }
  }

    property var routeStartPoint: undefined
    property var routeMidPoint: undefined
    property var routeEndPoint: undefined
    property var routeRequest: undefined
    property var routeJson: undefined
    property var apiKey: undefined
    property var routeProfile: "driving-car"



    function getRoute() {
        routeRequest = new XMLHttpRequest()
        routeRequest.onreadystatechange = () => {
            if (routeRequest.readyState === XMLHttpRequest.DONE) {
                routeJson = JSON.parse(routeRequest.response)
                processRoute()
            }
        }

        const start = routeStartPoint.x + "," + routeStartPoint.y
        const end = routeEndPoint.x + "," + routeEndPoint.y
        const routeProfile = settings.value("orstools/profile", "")
        const apiKey = settings.value("orstools/api_key", "")
        const url = "https://api.openrouteservice.org/v2/directions/" + routeProfile
            + "?api_key=" + apiKey
            + "&start=" + start
            + "&end=" + end

        routeRequest.open("GET", url)
        routeRequest.send()
    }

    function processRoute() {
        if (routeJson !== undefined) {
            let points = []
            for (let leg of routeJson['features']) {
                for (let coordinates of leg['geometry']['coordinates']) {
                    points.push(coordinates[0] + ' ' + coordinates[1])
                }
            }
            const wkt = "LINESTRING(" + points.join(",") + ")"
            routeRenderer.geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt(wkt)
        }
    }

}
