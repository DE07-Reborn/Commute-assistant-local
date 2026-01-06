"""
데이터베이스 모델
"""
from sqlalchemy import Column, BigInteger, String, Integer, Boolean, Time, DateTime, ForeignKey, DECIMAL
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from database import Base
from enum import Enum
from auth import hash_password


class Gender(str, Enum):
    """성별 Enum"""
    MALE = "male"
    FEMALE = "female"
    OTHER = "other"


class User(Base):
    """사용자 기본 정보 테이블"""
    __tablename__ = "users"

    id = Column(BigInteger, primary_key=True, index=True)
    user_id = Column(String, nullable=False, unique=True, index=True)
    password = Column(String, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    profile = relationship("UserProfile", back_populates="user", uselist=False)
    address = relationship("UserAddress", back_populates="user", uselist=False)
    events = relationship("Event", back_populates="user", uselist=False)

    def set_password(self, password: str):
        """비밀번호를 해싱하여 설정"""
        self.password = hash_password(password)


class UserProfile(Base):
    """사용자 프로필 정보 테이블"""
    __tablename__ = "user_profile"

    id = Column(BigInteger, ForeignKey("users.id"), primary_key=True)
    name = Column(String, nullable=False)
    gender = Column(String)
    commute_time = Column(Time)
    feedback_min = Column(Integer)

    user = relationship("User", back_populates="profile")


class UserAddress(Base):
    """사용자 주소 정보 테이블"""
    __tablename__ = "user_address"

    id = Column(BigInteger, ForeignKey("users.id"), primary_key=True)
    home_address = Column(String)
    home_lat = Column(DECIMAL(10, 7))
    home_lon = Column(DECIMAL(10, 7))
    work_address = Column(String)
    work_lat = Column(DECIMAL(10, 7))
    work_lon = Column(DECIMAL(10, 7))

    user = relationship("User", back_populates="address")


class Event(Base):
    """이벤트 알림 설정 테이블"""
    __tablename__ = "events"
    id = Column(BigInteger, ForeignKey("users.id"), primary_key=True)
    notify_before_departure = Column(Boolean, nullable=False, default=True, server_default="true")
    notify_mask = Column(Boolean, nullable=False, default=True, server_default="true")
    notify_umbrella = Column(Boolean, nullable=False, default=True, server_default="true")
    notify_clothing = Column(Boolean, nullable=False, default=True, server_default="true")
    notify_music = Column(Boolean, nullable=False, default=True, server_default="true")
    notify_book = Column(Boolean, nullable=False, default=True, server_default="true")
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now(), nullable=False)

    user = relationship("User", back_populates="events")


class FcmToken(Base):
    __tablename__ = "fcm_tokens"

    id = Column(BigInteger, primary_key=True, index=True)
    user_id = Column(BigInteger, ForeignKey("users.id"), nullable=False, index=True)
    token = Column(String, unique=True, nullable=False, index=True)
    platform = Column(String, default="android")
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    active = Column(Boolean, default=True, server_default="true")
