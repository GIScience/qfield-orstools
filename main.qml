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

    property var mainWindow: iface.mainWindow()
    property var mapCanvas: iface.mapCanvas()
    property var canvasMenu: iface.findItemByObjectName('canvasMenu')
    property var routeStartPoint: undefined
    property var routeMidPoint: undefined
    property var routeEndPoint: undefined
    property var routeRequest: undefined
    property var routeJson: undefined
    property var isochroneRequest: undefined
    property var isochroneJson: undefined
    property var apiKey: undefined
    property var routeProfile: "driving-car"
    property var profiles: ["driving-car", "driving-hgv", "cycling-regular", "cycling-road", "cycling-mountain", "cycling-electric", "foot-walking", "foot-hiking", "wheelchair"]

    function getRoute() {
        routeRequest = new XMLHttpRequest();
        routeRequest.onreadystatechange = () => {
            if (routeRequest.readyState === XMLHttpRequest.DONE) {
                routeJson = JSON.parse(routeRequest.response);
                processRoute();
            }
        };
        const start = routeStartPoint.x + "," + routeStartPoint.y;
        const end = routeEndPoint.x + "," + routeEndPoint.y;
        const profileIndex = settings.value("orstools/profile", 0);
        const routeProfile = profiles[profileIndex];
        const apiKey = settings.value("orstools/api_key", "");
        const url = "https://api.openrouteservice.org/v2/directions/" + routeProfile + "?api_key=" + apiKey + "&start=" + start + "&end=" + end;
        routeRequest.open("GET", url);
        routeRequest.send();
    }

    function getIsochrone() {
        isochroneRequest = new XMLHttpRequest();
        isochroneRequest.onreadystatechange = () => {
            if (isochroneRequest.readyState === XMLHttpRequest.DONE) {
                isochroneJson = JSON.parse(isochroneRequest.response);
                processIsochrone();
            }
        };
        
        const point = GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs);
        const profileIndex = settings.value("orstools/profile", 0);
        const routeProfile = profiles[profileIndex];
        const apiKey = settings.value("orstools/api_key", "");
        const rangeA = parseInt(settings.value("orstools/isochrone_range_a", "300"));
        const rangeB = parseInt(settings.value("orstools/isochrone_range_b", "600"));
        const rangeC = parseInt(settings.value("orstools/isochrone_range_c", "900"));
        const rangeType = settings.value("orstools/isochrone_range_type", 0) == 0 ? "time" : "distance";
        
        const url = "https://api.openrouteservice.org/v2/isochrones/" + routeProfile;
        const payload = {
            "locations": [[point.x, point.y]],
            "range": [rangeA, rangeB, rangeC],
            "range_type": rangeType
        };
        
        isochroneRequest.open("POST", url);
        isochroneRequest.setRequestHeader("Content-Type", "application/json; charset=utf-8");
        isochroneRequest.setRequestHeader("Authorization", apiKey);
        isochroneRequest.send(JSON.stringify(payload));
    }

    function processRoute() {
        if (routeJson !== undefined) {
            let points = [];
            for (let leg of routeJson['features']) {
                for (let coordinates of leg['geometry']['coordinates']) {
                    points.push(coordinates[0] + ' ' + coordinates[1]);
                }
            }
            const wkt = "LINESTRING(" + points.join(",") + ")";
            routeRenderer.geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt(wkt);
        }
    }

    function processIsochrone() {
        if (isochroneJson !== undefined && isochroneJson['features']) {
            let features = isochroneJson['features'].sort((a, b) => {
                return a.properties.value - b.properties.value;
            });            
            for (let i = 0; i < features.length; i++) {
                if (features[i]['geometry'] && features[i]['geometry']['coordinates']) {
                    let rings = [];
                    
                    for (let ring of features[i]['geometry']['coordinates']) {
                        let points = [];
                        for (let coord of ring) {
                            points.push(coord[0] + ' ' + coord[1]);
                        }
                        rings.push('(' + points.join(',') + ')');
                    }
                    
                    if (i > 0 && features[i-1]['geometry'] && features[i-1]['geometry']['coordinates']) {
                        for (let ring of features[i-1]['geometry']['coordinates']) {
                            let points = [];
                            for (let coord of ring) {
                                points.push(coord[0] + ' ' + coord[1]);
                            }
                            rings.push('(' + points.join(',') + ')');
                        }
                    }
                    
                    const wkt = "POLYGON(" + rings.join(',') + ")";
                    
                    if (isochroneRenderersRepeater && isochroneRenderersRepeater.itemAt(i)) {
                        isochroneRenderersRepeater.itemAt(i).geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt(wkt);
                    }
                }
            }
        }
    }
    
    property var isochroneColors: [ "#4c84af", "#fff764", "#f47f36" ]
    Repeater {
        id: isochroneRenderersRepeater
        model: plugin.isochroneColors
        QFieldItems.GeometryRenderer {
            parent: mapCanvas
            mapSettings: mapCanvas.mapSettings
            geometryWrapper.crs: CoordinateReferenceSystemUtils.wgs84Crs()
            color: modelData
            opacity: 0.6
            lineWidth: 2
        }
    }

    width: mainWindow.width
    height: mainWindow.height
    Component.onCompleted: {
        iface.addItemToCanvasActionsToolbar(routingPluginButtonsContainer);
        iface.addItemToPluginsToolbar(settingsButton);
    }

    QfToolButton {
        id: settingsButton

        iconSource: 'icon.png'
        round: true
        bgcolor: "white"
        onClicked: {
            routeStartPoint = undefined;
            routeEndPoint = undefined;
            routeRenderer.geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt("");
            for (let i = 0; i < isochroneRenderersRepeater.count; i++) {
                    isochroneRenderersRepeater.itemAt(i).geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt("");
            }   
            settingsDialog.open();
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
        standardButtons: Dialog.Ok
        onAccepted: {
            settings.setValue("orstools/api_key", apiKeyField.text);
            settings.setValue("orstools/profile", profileSelector.currentIndex);
            settings.setValue("orstools/isochrone_range_a", range_a.text);
            settings.setValue("orstools/isochrone_range_b", range_b.text);
            settings.setValue("orstools/isochrone_range_c", range_c.text);
            settings.setValue("orstools/isochrone_range_type", isochroneRangeType.currentIndex);
        }

        Column {
            spacing: 12
            width: parent.width


            Text {
                text: "General Settings"
            }

            TextField {
                id: apiKeyField

                width: parent.width
                placeholderText: "Enter API key"
                text: settings.value("orstools/api_key", "")
            }

            ComboBox {
                id: profileSelector

                width: 250
                model: profiles
                currentIndex: {
                    const saved = settings.value("orstools/profile", 0);                }
                popup.z: 10001
            }

            Text {
                text: "Isochrones"
            }

            Row {
                spacing: 10
                
                Column {
                    TextField {
                        id: range_a
                        width: 100
                        text: settings.value("orstools/isochrone_range_a", "300")
                        validator: IntValidator { bottom: 1; top: 100000 }
                        font: Theme.defaultFont
                    }
                    Text {
                        text: "Range A"
                        font: Theme.defaultFont
                    }
                }
                
                Column {
                    TextField {
                        id: range_b
                        width: 100
                        text: settings.value("orstools/isochrone_range_b", "600")
                        validator: IntValidator { bottom: 1; top: 100000 }
                        font: Theme.defaultFont
                    }
                    Text {
                        text: "Range B"
                        font: Theme.defaultFont
                    }
                }
                
                Column {
                    TextField {
                        id: range_c
                        width: 100
                        text: settings.value("orstools/isochrone_range_c", "900")
                        validator: IntValidator { bottom: 1; top: 100000 }
                        font: Theme.defaultFont
                    }
                    Text {
                        text: "Range C"
                        font: Theme.defaultFont
                    }
                }
            }

            ComboBox {
                id: isochroneRangeType

                width: 250
                model: ["time", "distance"]
                currentIndex: {
                    const saved = settings.value("orstools/isochrone_range_type", 0);
                }
            }
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
        id: routingPluginButtonsContainer

        width: childrenRect.width + 10
        height: 48
        radius: height / 2

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
                routeStartPoint = GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs);
                if (routeEndPoint != undefined)
                    getRoute();

                canvasMenu.close();
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
                routeEndPoint = GeometryUtils.reprojectPointToWgs84(canvasMenu.point, mapCanvas.mapSettings.destinationCrs);
                if (routeStartPoint != undefined)
                    getRoute();

                canvasMenu.close();
            }
        }

        QfToolButton {
            id: isochroneButton

            anchors.left: addEndPointButton.right
            anchors.leftMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - 10
            height: width
            iconSource: 'isochroneIcon.svg'
            iconColor: "white"
            round: true
            onClicked: {
                getIsochrone();
                canvasMenu.close();
            }
        }

        QfToolButton {
            id: clearPointsButton

            anchors.left: isochroneButton.right
            anchors.leftMargin: 5
            anchors.verticalCenter: parent.verticalCenter
            width: parent.height - 10
            height: width
            iconSource: 'routeClearIcon.svg'
            iconColor: "white"
            round: true
            enabled: routeStartPoint != undefined || routeEndPoint != undefined || isochroneRenderersRepeater.count > 0
            opacity: enabled ? 1 : 0.5
            onClicked: {
                routeStartPoint = undefined;
                routeEndPoint = undefined;
                routeRenderer.geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt("");
                for (let i = 0; i < isochroneRenderersRepeater.count; i++) {
                    isochroneRenderersRepeater.itemAt(i).geometryWrapper.qgsGeometry = GeometryUtils.createGeometryFromWkt("");
                }   
                canvasMenu.close();
            }
        }

        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: "#015491"
            }

            GradientStop {
                position: 1
                color: "#562b7a"
            }

        }

    }

}
