import os
import requests
import logging


class GoogleAPIUtils:
    """
        Util clasas for requesting google api 
    """
    BASE_URL = "https://routes.googleapis.com/directions/v2:computeRoutes"

    def __init__(self):
        self.api_key = os.getenv("GOOGLE_MAPS_API_KEY")

    def request_route_api(self, lon1, lat1, lon2, lat2, arrival_time):
        """
            Request Google API (route) as json
            param 
                lon1 : longitude of home address
                lat1 : latitude of home address
                lon2 : longitude of work address
                lat2 : latitude of work address
                arrival_time : estimated arrival time : 
        """

        headers = {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": self.api_key,
            "X-Goog-FieldMask": "routes.duration,routes.distanceMeters,routes.legs.steps"
        }
        
        data = {
            "origin": {
                "location": {
                    "latLng": {
                        "latitude": lat1,  
                        "longitude": lon1
                    }
                }
            },
            "destination": {
                "location": {
                    "latLng": {
                        "latitude": lat2,    
                        "longitude": lon2
                    }
                }
            },
            "travelMode": "TRANSIT",
            "arrivalTime": arrival_time,
        }

        try:
            response = requests.post(self.BASE_URL, headers=headers, json=data, timeout=10)
            if response.status_code != 200:
                logging.error(
                    "Routes API error: status=%s body=%s",
                    response.status_code,
                    response.text,
                )
            response.raise_for_status()
            return response.json()
        
        except Exception as e:
            logging.exception(f"Unexpected error caught while requesting Route API : {e}")
            raise
