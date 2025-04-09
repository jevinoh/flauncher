/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';
import 'dart:collection';
import 'package:collection/collection.dart' as collection;

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:tuple/tuple.dart';

import '../models/app.dart';
import '../models/category.dart';

import '../utils.dart';
import '../models/category.dart';


class AppsService extends ChangeNotifier
{
  final FLauncherChannel _fLauncherChannel;
  final FLauncherDatabase _database;

  bool _initialized = false;

  List<LauncherSection> _launcherSections = List.empty(growable: true);
  Map<String, App> _applications = Map();
  Map<int, Category> _categoriesById = Map();

  bool get initialized => _initialized;

  List<App> get applications => UnmodifiableListView(_applications.values.sortedBy((application) => application.name));

  List<LauncherSection> get launcherSections => List.unmodifiable(_launcherSections);
  List<Category> get categories => _categoriesById.values
      .map((category) => category.unmodifiable())
      .toList(growable: false);

  List<Map<String, dynamic>> featuredApps = [
    {"name": "Ziggapp", "packageName": "com.ziggapp.tv", "banner": "assets/banner-ziggapp.png"},
    {"name": "Netflix", "packageName": "com.netflix.ninja", "banner": "assets/banner-netflix.png"},
    {"name": "Hulu", "packageName": "com.hulu.plus", "banner": "assets/banner-hulu.png"},
    {"name": "Amazon Prime video", "packageName": "com.amazon.amazonvideo.livingroom", "banner": "assets/banner-amazonprime.png"}
  ];

  AppsService(this._fLauncherChannel, this._database) {
    _init();
  }

  Future<void> _init() async {
    await _refreshState(shouldNotifyListeners: false);
    if (_database.wasCreated) {
      await _initDefaultCategories();
    }

    _fLauncherChannel.addAppsChangedListener((event) async {
      logDebug("event action ${event["action"]}");
      switch (event["action"]) {
        case "PACKAGE_ADDED":
        case "PACKAGE_CHANGED":
          Map<dynamic, dynamic> applicationInfo = event['activityInfo'];
          await _database.persistApps([_buildAppCompanion(applicationInfo)]);

          App application = App.fromSystem(applicationInfo);
          _applications[application.packageName] = application;
          break;
        case "PACKAGES_AVAILABLE":
          List<dynamic> applicationsInfo = event["activitiesInfo"];
          await _database.persistApps((applicationsInfo).map(_buildAppCompanion));

          for (Map<dynamic, dynamic> applicationInfo in applicationsInfo) {
            App application = App.fromSystem(applicationInfo);
            _applications[application.packageName] = application;
          }
          break;
        case "PACKAGE_REMOVED":
          String packageName = event['packageName'];
          await _database.deleteApps([packageName]);

          App? application = _applications.remove(packageName);

          if (application != null) {
            for (int categoryId in application.categoryOrders.keys) {
              if (_categoriesById.containsKey(categoryId)) {
                Category category = _categoriesById[categoryId]!;
                category.applications.remove(application);
              }
            }
          }
          break;
      }

      notifyListeners();
    });

    _initialized = true;
    notifyListeners();
  }

  AppsCompanion _buildAppCompanion(dynamic data) {
    String? version = data["version"];
    if (version == null) {
      version = "";
    }

    return AppsCompanion(
        packageName: Value(data["packageName"]),
        name: Value(data["name"]),
        version: Value(version),
        hidden: const Value.absent()
      );
  }

  Future<void> _initDefaultCategories() {
    // final tvApplications = _applications.values.where((application) => application.sideloaded == false);
    // final nonTvApplications = _applications.values.where((application) => application.sideloaded == true);

    return _database.transaction(() async {
      // if (tvApplications.isNotEmpty) {
      //   logDebug("addCategory : My Lists");
      //   int categoryId = await addCategory("My Lists",
      //       type: CategoryType.row, shouldNotifyListeners: false
      //   );
      //
      //   Category tvAppsCategory = _categoriesById[categoryId]!;
      //   tvAppsCategory.sort = CategorySort.manual;
      //   for (final app in tvApplications) {
      //     await addToCategory(app, tvAppsCategory, shouldNotifyListeners: false);
      //   }
      //
      //   sortCategory(tvAppsCategory);
      //
      // }
      // if (nonTvApplications.isNotEmpty) {
      //   int categoryId = await addCategory("Non-TV Applications",
      //     shouldNotifyListeners: false,
      //   );
      //   Category nonTvAppsCategory = _categoriesById[categoryId]!;
      //   for (final app in nonTvApplications) {
      //     await addToCategory(app, nonTvAppsCategory, shouldNotifyListeners: false);
      //   }
      // }
    });
  }

  Future<void> _refreshState({bool shouldNotifyListeners = true}) async {
    Future<List<App>> appsFromDatabaseFuture = _database.getApplications();
    Future<List<AppCategory>> appsCategoriesFuture = _database.getAppsCategories();
    Future<List<Category>> categoriesFuture = _database.getCategories();
    Future<List<LauncherSpacer>> spacersFuture = _database.getLauncherSpacers();
    List<Map<dynamic, dynamic>> appsFromSystem = await _fLauncherChannel.getApplications();
    Iterable<MapEntry<String, Tuple2<Map, AppsCompanion>>> appEntries = appsFromSystem.map(
            (appFromSystem) => new MapEntry(appFromSystem['packageName'], Tuple2(appFromSystem, _buildAppCompanion(appFromSystem))));
    Map<String, Tuple2<Map, AppsCompanion>> appsFromSystemByPackageName = Map.fromEntries(appEntries);

    for (var entry in appEntries) {
      logDebug("appEntries - Package Name: ${entry.key}");
    }

    for (var entry in appsFromSystemByPackageName.entries) {
      logDebug("appsFromSystemByPackageName - Package Name: ${entry.key}");
    }

    List<App> appsFromDatabase = await appsFromDatabaseFuture;
    final Iterable<App> appsRemovedFromSystem = appsFromDatabase
        .where((app) => !appsFromSystemByPackageName.containsKey(app.packageName));

    for (var app in appsFromDatabase) {
      logDebug("appsFromDatabase - Package Name: ${app.packageName}");
    }

    for (var app in appsRemovedFromSystem) {
      logDebug("appsRemovedFromSystem - Package Name: ${app.packageName}");
    }

    final List<String> uninstalledApplications = [];
    for (App app in appsRemovedFromSystem) {
      String packageName = app.packageName;

      // TODO: Is this really necessary? Can't we get this information from the getApplications method?
      bool appExists = await _fLauncherChannel.applicationExists(packageName);
      if (!appExists) {
        logDebug("uninstalledApplications - Package Name: ${packageName}");
        uninstalledApplications.add(packageName);
      }
    }

    await _database.transaction(() async {
      await _database.persistApps(appsFromSystemByPackageName.values.map((tuple) => tuple.item2));
      await _database.deleteApps(uninstalledApplications);
    });

    appsFromDatabaseFuture = _database.getApplications();

    await Future.wait([appsFromDatabaseFuture, appsCategoriesFuture, categoriesFuture, spacersFuture]);

    appsFromDatabase = await appsFromDatabaseFuture;
    List<AppCategory> appsCategories = await appsCategoriesFuture;
    List<Category> categories = [];
    List<LauncherSpacer> spacers = await spacersFuture;

    // categories.removeWhere((category) => category.id == 2);

    for (var category in appsCategories) {
      logDebug("appsCategories - ID[${category.categoryId}] Name[${category.appPackageName}]");
    }

    Category featured = new Category(
      name: "Featured Apps",
      id: CategoryID.featureApps.index,
      order: 0,
      columnsCount: 6,
      rowHeight: 110,
      sort: CategorySort.manual,
      type: CategoryType.row,
    );

    categories.add(featured);

    Category appLists = new Category(
      name: "My Lists",
      id: CategoryID.apps.index,
      order: 0,
      columnsCount: 6,
      rowHeight: 110,
      sort: CategorySort.activeTime,
      type: CategoryType.row,
    );

    categories.add(appLists);

    for (var category in categories) {
      logDebug("categories - name[${category.name}] id[${category.id}] order[${category.order}] columnsCount[${category.columnsCount}] rowHeight[${category.rowHeight}] sort[${category.sort}] type[${category.type}]");
    }


    _categoriesById = Map.fromEntries(categories.map((category) => MapEntry(category.id, category)));
    _applications = Map.fromEntries(appsFromDatabase.map((application) => MapEntry(application.packageName, application)));

    for (var app in _applications.entries) {
      logDebug("_applications - Name[${app.value.packageName}]");
    }

    for (var category in _categoriesById.entries) {
      logDebug("_categoriesById - ID[${category.value.id}] Name[${category.value.name}]");
    }

    _launcherSections.clear();
    _launcherSections.addAll(categories);
    _launcherSections.addAll(spacers);
    _launcherSections.sort((ls0, ls1) => ls0.order.compareTo(ls1.order));

    for (App application in _applications.values) {
      Map? applicationFromSystem = appsFromSystemByPackageName[application.packageName]?.item1;

      if (applicationFromSystem != null) {
        if (applicationFromSystem.containsKey('action')) {
          application.action = applicationFromSystem['action'];
        }
        if (applicationFromSystem.containsKey('sideloaded')) {
          application.sideloaded = applicationFromSystem['sideloaded'];
        }
      }

      if (!application.hidden) {
        bool exists = featuredApps.any((app) => app["packageName"] == application.packageName);
        if (_categoriesById.containsKey(CategoryID.featureApps.index) && exists) {
          Category category = _categoriesById[CategoryID.featureApps.index]!;
          application.categoryOrders[category.id] = CategorySort.manual.index;
          category.applications.add(application);
        }
        else if (_categoriesById.containsKey(CategoryID.apps.index) && application.packageName != "me.efesser.flauncher") {
          Category category = _categoriesById[CategoryID.apps.index]!;
          application.categoryOrders[category.id] = CategorySort.manual.index;
          category.applications.add(application);
        }
      }
    }

    for (var featured in featuredApps) {
      String packageName = featured["packageName"];
      bool found = false;
      App appInfo;
      for (var app in _categoriesById[CategoryID.featureApps.index]!.applications) {
        if (app.packageName == packageName) {
          found = true;
          break;
        }
      }

      if (!found) {
        App appInfo = new App(
                            packageName : packageName,
                            name : featured["name"],
                            version : "0",
                            hidden : false,
                            action : null,
                            deeplinkUrl : "https://play.google.com/store/apps/details?id=" + packageName,
                            banner : featured["banner"]
        );

        _categoriesById[CategoryID.featureApps.index]!.applications.add(appInfo);
      }
    }


    for (Category category in _categoriesById.values) {
      sortCategory(category);
    }

    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  void sortCategory(Category category) {
    logDebug("start");

    if(category.id == CategoryID.featureApps.index)
    {
      logDebug("featureApps sort");
      // priority app packagenames in the specific order
      // TODO: find the zigapp apk to check it's actual packagename
      final priorityApps = ['com.ziggapp.tv', 'com.netflix.ninja', 'com.hulu.plus', 'com.amazon.amazonvideo.livingroom'];

      category.applications.sort((a, b) {
        final indexA = priorityApps.indexWhere((name) => a.packageName.toLowerCase().contains(name));
        final indexB = priorityApps.indexWhere((name) => b.packageName.toLowerCase().contains(name));

        final isAInPriority = indexA != -1;
        final isBInPriority = indexB != -1;

        // Both in priority list → sort by defined order
        if (isAInPriority && isBInPriority) {
          return indexA.compareTo(indexB);
        }

        // Only A is in priority list → A comes first
        if (isAInPriority) return -1;

        // Only B is in priority list → B comes first
        if (isBInPriority) return 1;

        // Neither is in priority list → keep existing order
        return 0;
      });
    }
    else if(category.id == CategoryID.apps) {
      // Do nothing for now
      logDebug("apps sort");
    }

  }


  Future<Uint8List> getAppBanner(String packageName) {
    return _fLauncherChannel.getApplicationBanner(packageName);
  }

  Future<Uint8List> getAppIcon(String packageName) {
    return _fLauncherChannel.getApplicationIcon(packageName);
  }

  Future<void> launchApp(App app) {
    Future<void> future;
    if (app.action == null && app.deeplinkUrl == null) {
      future = _fLauncherChannel.launchApp(app.packageName);
    }
    else if (app.action == null && app.deeplinkUrl != null) {
      future = _fLauncherChannel.launchAppDeeplink(app.packageName);
    }
    else {
      future = _fLauncherChannel.launchActivityFromAction(app.action!);
    }

    return future;
  }

  Future<void> openAppInfo(App app) => _fLauncherChannel.openAppInfo(app.packageName);

  Future<void> uninstallApp(App app) => _fLauncherChannel.uninstallApp(app.packageName);

  Future<void> openSettings() => _fLauncherChannel.openSettings();

  Future<bool> isDefaultLauncher() => _fLauncherChannel.isDefaultLauncher();

  Future<void> startAmbientMode() => _fLauncherChannel.startAmbientMode();

  Future<void> addToCategory(App app, Category category, {bool shouldNotifyListeners = true}) async {
    int index = await _database.nextAppCategoryOrder(category.id) ?? 0;
    logDebug("insertAppsCategories - Name: ${category.name}");

    await _database.insertAppsCategories([
      AppsCategoriesCompanion.insert(
        categoryId: category.id,
        appPackageName: app.packageName,
        order: index,
      )
    ]);

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      app.categoryOrders[categoryFound.id] = index;
      categoryFound.applications.add(app);

      if (shouldNotifyListeners) {
        sortCategory(categoryFound);
        notifyListeners();
      }
    }
  }

  Future<void> removeFromCategory(App application, Category category) async {
    await _database.deleteAppCategory(category.id, application.packageName);
    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      application.categoryOrders.remove(categoryFound.id);
      categoryFound.applications.remove(application);

      notifyListeners();
    }
  }

  Future<void> saveApplicationOrderInCategory(Category category) async {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }
    
    Category categoryFound = _categoriesById[category.id]!;
    List<App> applications = categoryFound.applications;
    List<AppsCategoriesCompanion> orderedAppCategories = [];

    for (int i = 0; i < applications.length; ++i) {
      orderedAppCategories.add(AppsCategoriesCompanion(
        categoryId: Value(categoryFound.id),
        appPackageName: Value(applications[i].packageName),
        order: Value(i),
      ));
    }
    await _database.replaceAppsCategories(orderedAppCategories);
    notifyListeners();
  }

  void reorderApplication(Category category, int oldIndex, int newIndex) {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }
    Category categoryFound = _categoriesById[category.id]!;
    List<App> applications = categoryFound.applications;
    App application = applications.removeAt(oldIndex);
    applications.insert(newIndex, application);

    notifyListeners();
  }

  Future<int> addCategory(String categoryName, {
    CategorySort sort = Category.Sort,
    CategoryType type = Category.Type,
    int columnsCount = Category.ColumnsCount,
    int rowHeight = Category.RowHeight,
    bool shouldNotifyListeners = true
  }) async {
    logDebug("Category Name: ${categoryName}");

    List<CategoriesCompanion> orderedCategories = [];
    int categoryOrder = 1, newCategoryId = -1;
    for (Category category in _categoriesById.values) {
      orderedCategories.add(CategoriesCompanion(id: Value(category.id), order: Value(categoryOrder++)));
    }

    try {
      newCategoryId = await _database.transaction(() async {
        int newCategoryId = await _database.insertCategory(CategoriesCompanion.insert(name: categoryName, order: 0));
        await _database.updateCategories(orderedCategories);

        return newCategoryId;
      });

      Map<int, Category> newCategories = Map();
      Category newCategory = Category(
          id: newCategoryId,
          name: categoryName,
          sort: sort,
          type: type,
          columnsCount: columnsCount,
          rowHeight: rowHeight,
          order: 0
      );
      newCategories[newCategoryId] = newCategory;

      categoryOrder = 1;
      for (Category category in _categoriesById.values) {
        newCategories[category.id] = category;
        category.order = categoryOrder++;
      }

      _categoriesById = newCategories;
      _launcherSections.add(newCategory);

      if (shouldNotifyListeners) {
        notifyListeners();
      }

    }
    catch (ex) { }

    return newCategoryId;
  }

  Future<void> updateCategory(
    int categoryId,
    String name,
    CategorySort sort,
    CategoryType type,
    int columnsCount,
    int rowHeight, {
    bool shouldNotifyListeners = true
    }) async
  {
    logDebug("Category Name: ${name}");

    Category? category = _categoriesById[categoryId];
    assert(category != null);

    await _database.updateCategory(categoryId, CategoriesCompanion(
      name: Value(name),
      sort: Value(sort),
      type: Value(type),
      columnsCount: Value(columnsCount),
      rowHeight: Value(rowHeight)
    ));

    CategorySort oldSort = category!.sort;

    category.name = name;
    category.sort = sort;
    category.type = type;
    category.columnsCount = columnsCount;
    category.rowHeight = rowHeight;

    if (oldSort != sort) {
      sortCategory(category);
    }

    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> addSpacer(int height) async
  {
    int order = launcherSections.length;
    int spacerId = await _database.insertSpacer(
        LauncherSpacersCompanion.insert(height: height, order: order)
    );

    _launcherSections.add(LauncherSpacer(
      id: spacerId,
      height: height,
      order: order
    ));

    notifyListeners();
  }

  Future<void> updateSpacerHeight(LauncherSpacer spacer, int height) async
  {
    await _database.updateSpacer(spacer.id, LauncherSpacersCompanion(
      height: Value(height)
    ));

    spacer.height = height;
    notifyListeners();
  }

  Future<void> renameCategory(Category category, String categoryName) async {
    logDebug("updateCategory -> Name: ${category.name}");

    await _database.updateCategory(category.id, CategoriesCompanion(name: Value(categoryName)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.name = categoryName;
      notifyListeners();
    }
  }

  Future<void> deleteSection(int index) async
  {
    assert(index < _launcherSections.length);

    LauncherSection section = _launcherSections[index];
    if (section is Category) {
      await _database.deleteCategory(section.id);
      _categoriesById.remove(section.id);
    }
    else {
      await _database.deleteSpacer(section.id);
    }
    
    _launcherSections.removeAt(index);

    notifyListeners();
  }

  Future<void> moveSection(int oldIndex, int newIndex) async {
    List<LauncherSection> newSectionsList = List.of(_launcherSections);
    LauncherSection sectionToMove = newSectionsList.removeAt(oldIndex);
    newSectionsList.insert(newIndex, sectionToMove);

    List<CategoriesCompanion> orderedCategories = [];
    List<LauncherSpacersCompanion> orderedSpacers = [];
    for (int i = 0; i < newSectionsList.length; ++i) {
      LauncherSection section = newSectionsList[i];

      if (section is Category) {
        orderedCategories.add(CategoriesCompanion(id: Value(section.id), order: Value(i)));
      }
      else {
        orderedSpacers.add(LauncherSpacersCompanion(id: Value(section.id), order: Value(i)));
      }
    }

    await Future.wait([
      _database.updateCategories(orderedCategories),
      _database.updateSpacers(orderedSpacers)
    ]);

    _launcherSections = newSectionsList;
    notifyListeners();
  }

  Future<void> hideApplication(App application) async {
    await _database.updateApp(application.packageName, const AppsCompanion(hidden: Value(true)));

    if (_applications.containsKey(application.packageName)) {
      App applicationFound = _applications[application.packageName]!;
      applicationFound.hidden = true;

      for (int categoryId in applicationFound.categoryOrders.keys) {
        if (_categoriesById.containsKey(categoryId)) {
          Category category = _categoriesById[categoryId]!;
          category.applications.removeWhere((application0) => application0.packageName == application.packageName);
        }
      }

      notifyListeners();
    }
  }

  Future<void> showApplication(App application) async {
    await _database.updateApp(application.packageName, const AppsCompanion(hidden: Value(false)));

    if (_applications.containsKey(application.packageName)) {
      App applicationFound = _applications[application.packageName]!;
      applicationFound.hidden = false;

      for (int categoryId in application.categoryOrders.keys) {
        if (_categoriesById.containsKey(categoryId)) {
          Category category = _categoriesById[categoryId]!;
          category.applications.add(application);
          sortCategory(category);
        }
      }

      notifyListeners();
    }
  }

  Future<void> setCategoryType(Category category, CategoryType type, {bool shouldNotifyListeners = true}) async {
    await _database.updateCategory(category.id, CategoriesCompanion(type: Value(type)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.type = type;

      if (shouldNotifyListeners) {
        notifyListeners();
      }
    }
  }

  Future<void> setCategorySort(Category category, CategorySort sort) async {
    await _database.updateCategory(category.id, CategoriesCompanion(sort: Value(sort)));
    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.sort = sort;
      sortCategory(categoryFound);

      notifyListeners();
    }

  }

  Future<void> setCategoryColumnsCount(Category category, int columnsCount) async {
    await _database.updateCategory(category.id, CategoriesCompanion(columnsCount: Value(columnsCount)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.columnsCount = columnsCount;

      notifyListeners();
    }
  }

  Future<void> setCategoryRowHeight(Category category, int rowHeight) async {
    await _database.updateCategory(category.id, CategoriesCompanion(rowHeight: Value(rowHeight)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.rowHeight = rowHeight;
      notifyListeners();
    }
  }
}
