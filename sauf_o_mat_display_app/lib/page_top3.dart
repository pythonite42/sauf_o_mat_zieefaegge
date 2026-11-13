import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sauf_o_mat_display_app/backend_connection.dart';
import 'package:sauf_o_mat_display_app/theme.dart';
import 'package:sauf_o_mat_display_app/globals.dart';

class GroupData {
  String logoUrl;
  String name;
  int longdrink;
  int beer;
  int shot;
  int luz;
  int points;

  GroupData({
    required this.logoUrl,
    required this.name,
    required this.longdrink,
    required this.beer,
    required this.shot,
    required this.luz,
    required this.points,
  });
}

double parchmentImageAspectRatio = 0.86; //seitenverhältnis von parchment.png

class PageTop3 extends StatefulWidget {
  const PageTop3({super.key});

  @override
  State<PageTop3> createState() => _PageTop3State();
}

class _PageTop3State extends State<PageTop3> {
  List<GroupData> _groupData = [];
  List<Map> _backgroundImages = [];

  late Timer _dataReloadTimer;

  @override
  void initState() {
    super.initState();

    _loadData();
    _startAutoReloadData();
    _loadBackgroundImages();
  }

  void _startAutoReloadData() {
    _dataReloadTimer = Timer.periodic(
      Duration(seconds: customDurations.reloadDataTop3),
      (_) {
        _loadData();
      },
    );
  }

  Future<void> _loadData() async {
    try {
      List<Map> newDataMapList = await SalesforceService().getPageTop3();
      newDataMapList.sort((a, b) => b["punktzahl"].compareTo(a["punktzahl"]));

      if (mounted) {
        setState(() {
          _groupData.clear();
          for (var element in newDataMapList) {
            _groupData.add(
              GroupData(
                logoUrl: element["groupLogo"],
                name: element["name"],
                longdrink: element["longdrink"],
                beer: element["beer"],
                shot: element["shot"],
                luz: element["luz"],
                points: element["punktzahl"],
              ),
            );
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching chart data: $e');
    }
  }

  Future<void> _loadBackgroundImages() async {
    try {
      List<Map> newDataMapList = await SalesforceService()
          .getPageTop3BackgroundImages();

      if (mounted) {
        setState(() {
          for (var element in newDataMapList) {
            _backgroundImages.add({
              "name": element["name"],
              "imageUrl": element["imageUrl"],
            });
          }
        });
      }
      debugPrint(_backgroundImages.toString());
    } catch (e) {
      debugPrint('Error fetching chart data: $e');
    }
  }

  @override
  void dispose() {
    _dataReloadTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    double size1 = MySize(context).w * 0.42;
    double size2 = MySize(context).w * 0.4;
    double size3 = MySize(context).w * 0.37;
    double backgroundImageSize = MySize(context).w * 0.3;
    return Stack(
      children: [
        (_groupData.isEmpty)
            ? Positioned(
                top: MySize(context).h * 0.5,
                left: MySize(context).w * 0.5,
                child: CircularProgressIndicator(color: defaultOnPrimary),
              )
            : Stack(
                children: [
                  //background Images:
                  if (_backgroundImages.isNotEmpty)
                    Positioned(
                      left: MySize(context).w * 0.05,
                      top: -MySize(context).h * 0.04,
                      child: ImagePoster(
                        size: backgroundImageSize,
                        name: _backgroundImages[0]["name"],
                        imageUrl: _backgroundImages[0]["imageUrl"],
                      ),
                    ),
                  if (_backgroundImages.length > 1)
                    Positioned(
                      right: MySize(context).w * 0.02,
                      top: MySize(context).h * 0.05,
                      child: ImagePoster(
                        size: backgroundImageSize,
                        name: _backgroundImages[1]["name"],
                        imageUrl: _backgroundImages[1]["imageUrl"],
                      ),
                    ),
                  if (_backgroundImages.length > 2)
                    Positioned(
                      left: MySize(context).w * 0.39,
                      bottom: -MySize(context).h * 0.22,
                      child: ImagePoster(
                        size: backgroundImageSize,
                        name: _backgroundImages[2]["name"],
                        imageUrl: _backgroundImages[2]["imageUrl"],
                      ),
                    ),

                  //top3 posters:
                  Positioned(
                    bottom: MySize(context).h * 0.01,
                    right: MySize(context).w * 0.04,
                    child: WantedPoster(
                      data: _groupData[2],
                      place: 3,
                      size: size3,
                    ),
                  ),
                  Positioned(
                    top: MySize(context).h * 0.24,
                    left: MySize(context).w * 0.02,
                    child: WantedPoster(
                      data: _groupData[1],
                      place: 2,
                      size: size2,
                    ),
                  ),
                  Positioned(
                    left:
                        (MySize(context).w / 2) -
                        (size1 * parchmentImageAspectRatio / 2),
                    top: -MySize(context).h * 0.03,
                    child: WantedPoster(
                      data: _groupData[0],
                      place: 1,
                      size: size1,
                    ),
                  ),
                ],
              ),
      ],
    );
  }
}

class ImagePoster extends StatelessWidget {
  const ImagePoster({
    super.key,
    required this.size,
    required this.name,
    required this.imageUrl,
  });
  final double size;
  final String name;
  final String imageUrl;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size * parchmentImageAspectRatio,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/parchment.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: size * 0.1,
            vertical: size * 0.06,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: size * 0.02),
                child: Text(
                  name,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.rye(
                    textStyle: TextStyle(fontSize: size * 0.06),
                  ),
                ),
              ),
              Expanded(
                child: Image.network(
                  imageUrl,
                  height: size * 0.6,
                  errorBuilder: (context, error, stackTrace) => SizedBox(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WantedPoster extends StatelessWidget {
  const WantedPoster({
    super.key,
    required this.data,
    required this.place,
    required this.size,
  });

  final GroupData data;
  final int place;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bodyTextStyle = TextStyle(
      fontSize: size * 0.05,
      fontWeight: FontWeight.bold,
      height: 1.0,
    );
    return Container(
      height: size,
      width: size * parchmentImageAspectRatio,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/parchment.png'),
          fit: BoxFit.cover, // cover entire container
        ),
      ),
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: size * 0.04,
            vertical: size * 0.02,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'WANTED',
                style: GoogleFonts.rye(
                  textStyle: TextStyle(fontSize: size * 0.09, height: 1.2),
                ),
              ),
              Divider(
                thickness: 2,
                height: size * 0.02,
                indent: size * 0.04,
                endIndent: size * 0.04,
              ),
              Text(
                'Staatsfeind Nr. $place',
                style: GoogleFonts.rye(
                  textStyle: TextStyle(fontSize: size * 0.05),
                ),
              ),
              Text(
                data.name,
                style: TextStyle(
                  fontSize: size * 0.06,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              Divider(
                thickness: 2,
                indent: size * 0.04,
                endIndent: size * 0.04,
              ),
              SizedBox(height: size * 0.005),
              Image.network(
                data.logoUrl,
                height: size * 0.3,
                errorBuilder: (context, _, _) => Image.asset(
                  'assets/placeholder_group.png',
                  height: size * 0.32,
                ),
              ),
              SizedBox(height: size * 0.01),
              SizedBox(
                height: size * 0.27,
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Gesucht für",
                          style: GoogleFonts.rye(
                            textStyle: TextStyle(fontSize: size * 0.05),
                          ),
                        ),
                        Text(
                          data.points.toString(),
                          style: GoogleFonts.rye(
                            textStyle: TextStyle(
                              fontSize: size * 0.07,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          "Punkte",
                          style: GoogleFonts.rye(
                            textStyle: TextStyle(fontSize: size * 0.05),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      height: size * 0.25,
                      child: VerticalDivider(
                        color: Colors.black,
                        thickness: 2,
                        width: size * 0.05,
                      ),
                    ),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        spacing: size * 0.02,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: size * 0.01,
                            children: [
                              Text("${data.longdrink}", style: bodyTextStyle),
                              Text("${data.beer}", style: bodyTextStyle),
                              Text("${data.shot}", style: bodyTextStyle),
                              Text("${data.luz}", style: bodyTextStyle),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            spacing: size * 0.01,
                            children: [
                              Text("Bargetränke", style: bodyTextStyle),
                              Text("Bier", style: bodyTextStyle),
                              Text("Shots", style: bodyTextStyle),
                              Text("Luz", style: bodyTextStyle),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
