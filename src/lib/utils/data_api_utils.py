import requests
import os

class Data_api_collector:
    """
        API util for data.go.kr
            - get ultra short term forecast
    """
    def __init__(self, ymd, hm):
        """
            Initialize Class
            param
                ymd : YearMonthDay
                hm : HHMM (HourMinute)
        """
        self.ymd = ymd
        self.hm = hm

        # api key
        self.key = os.getenv('DATA_KEY')
        if not self.key:
            raise EnvironmentError("DATA_KEY is not set in environment variables")
        
        # Default timeout 
        self.base_timeout = 30

    def request_getUltraSrtFcst_api(self, nx, ny):
        """
            request forecast data of nx, ny 
            param
                nx : calculated x coordinate 
                ny : calculated y coordinate
        """
        url = 'http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtFcst'
        params = {
            'serviceKey' : self.key, 
            'pageNo' : '1', 
            'numOfRows' : '1000', 
            'dataType' : 'JSON', 
            'base_date' : self.ymd, 
            'base_time' : self.hm, 
            'nx' : nx, 
            'ny' : ny 
        }

        response = requests.get(url, params=params)
        return response.json()
    
