from zoneinfo import ZoneInfo

KST = ZoneInfo("Asia/Seoul")

class RouteService:
    '''
        Request API from Google Route and normalize its response
    '''
    def __init__(self, google_api):
        self.google_api = google_api

    def fetch_route(self, message):
        '''
            based on the message in topic, request route api to 
            get its route information and normalize
            param
                message : The payload from producer via topic
        '''

        origin = message["origin"]
        destination = message["destination"]

        raw = self.google_api.request_route_api(
            lon1=origin["lon"],
            lat1=origin["lat"],
            lon2=destination["lon"],
            lat2=destination["lat"],
            arrival_time=message["arrive_by"],
        )
        return self._normalize(raw)


    def _normalize(self, raw):
        '''
            Normalize the response 
            param
                raw : Raw response from route API
        '''
        route = raw["routes"][0]

        total_duration_sec = int(float(route["duration"].rstrip("s")))
        total_distance_m = route.get("distanceMeters", 0)

        segments = []

        # Google response guarantees at least one leg
        for step in route["legs"][0]["steps"]:
            segment = {
                "type": step["travelMode"].lower(),  # walk / transit
                "duration_sec": int(
                    step["staticDuration"].replace("s", "")
                ),
                "distance_m": step.get("distanceMeters", 0),
                "polyline": step.get("polyline", {}).get(
                    "encodedPolyline"
                ),
                "start_location": step["startLocation"]["latLng"],
                "end_location": step["endLocation"]["latLng"],
                "instruction": step.get("navigationInstruction", {}).get("instructions"),
                "localized": step.get("localizedValues"),
            }

            # Transit-specific information
            if step["travelMode"] == "TRANSIT":
                td = step["transitDetails"]

                segment["transit"] = {
                    "line": td["transitLine"].get("nameShort"),
                    "line_color": td["transitLine"].get("color"),
                    "text_color": td["transitLine"].get("textColor"),
                    "vehicle": td["transitLine"]["vehicle"]["type"],
                    "vehicle_icon": td["transitLine"]["vehicle"].get("iconUri"),

                    "headsign": td.get("headsign"),
                    "headway_sec": int(td.get("headway", "0s").rstrip("s"))
                    if td.get("headway") else None,

                    "departure_stop": {
                        "name": td["stopDetails"]["departureStop"]["name"],
                        "location": td["stopDetails"]["departureStop"]["location"]["latLng"],
                    },
                    "arrival_stop": {
                        "name": td["stopDetails"]["arrivalStop"]["name"],
                        "location": td["stopDetails"]["arrivalStop"]["location"]["latLng"],
                    },

                    "departure_time": td["stopDetails"]["departureTime"],
                    "arrival_time": td["stopDetails"]["arrivalTime"],
                    "stop_count": td.get("stopCount"),
                }

            segments.append(segment)

        return {
            "total_duration_sec": total_duration_sec,
            "total_distance_m": total_distance_m,
            "segments": segments,
        }