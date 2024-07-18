#pragma once

#include "geometry/point2d.hpp"

#include "base/visitor.hpp"

#include <string>
#include <vector>

namespace geo_elements
{

struct User
{
  DECLARE_VISITOR(visitor(id, "id"), visitor(createdAt, "createdAt"), visitor(updatedAt, "updatedAt"),
                  visitor(firstName, "firstName"), visitor(email, "email"))

  int64_t id;
  std::string createdAt;
  std::string updatedAt;
  std::string firstName;
  // TODO: Find a way to handle optional fields
  // std::string lastName;
  // std::string middleName;
  std::string email;
};

struct Category
{
  DECLARE_VISITOR(visitor(id, "id"), visitor(createdAt, "createdAt"), visitor(updatedAt, "updatedAt"),
                  visitor(name, "name"), visitor(description, "description"))

  int64_t id;
  std::string createdAt;
  std::string updatedAt;
  std::string name;
  std::string description;
};

struct Position
{
  DECLARE_VISITOR(visitor(lat, "lat"), visitor(lng, "lng"))

  double lat;
  double lng;
};

struct GeoElement
{
  DECLARE_VISITOR(visitor(id, "id"), visitor(createdAt, "createdAt"), visitor(updatedAt, "updatedAt"),
                  visitor(title, "title"), visitor(description, "description"), visitor(isPublished, "isPublished"),
                  visitor(UserId, "UserId"), visitor(CategoryId, "CategoryId"), visitor(user, "user"),
                  visitor(category, "category"), visitor(type, "type"), visitor(position, "position"))

  int64_t id;
  std::string createdAt;
  std::string updatedAt;
  std::string title;
  std::string description;
  bool isPublished;
  int64_t UserId;
  int64_t CategoryId;
  User user;
  Category category;
  std::string type;
  Position position;
};

using GeoElements = std::vector<GeoElement>;

}  // namespace geo_elements